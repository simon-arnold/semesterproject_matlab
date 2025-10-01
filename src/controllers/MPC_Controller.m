classdef MPC_Controller < handle
    properties
        % MPC Parameters
        T_pred      % Prediction Time/horizon
        N_pred      % Prediction Horizon steps
        T_s         % Sampling Time/delta t
        nx = 1; 

        R_cost
        
        % System Parameters
        % Battery System
        nu_ch
        nu_dch      % charging & decharging efficiencies
        L_bat       % battery loss
        E_bat       % battery capacity
        DOD         % Depth of Discharge

        % Max Transmission Power
        P_batconv_max
        P_gridcons_max

        % YALMIP Optimizer
        controller  % Optimizer Object
    end
    
    methods
        function obj = MPC_Controller(T_pred, N_pred, T_s, R_cost, ...
                                      nu_ch, nu_dch, L_bat, E_bat, ...
                                      DOD, P_batconv_max, P_gridcons_max)
            % Konstruktor: System und MPC Parameter initialisieren
            obj.T_pred = T_pred;
            obj.N_pred = N_pred;
            obj.T_s = T_s;
            obj.R_cost = R_cost;
            obj.nu_ch = nu_ch;
            obj.nu_dch = nu_dch;
            obj.L_bat = L_bat;
            obj.E_bat = E_bat;
            obj.DOD = DOD;
            obj.P_batconv_max = P_batconv_max;
            obj.P_gridcons_max = P_gridcons_max;

            % Optimierungsproblem aufbauen
            obj.constructOptimizationProblem();
        end
        
        function constructOptimizationProblem(obj)
            
            % Parameters
            x1 = sdpvar(obj.nx,1);     
            p_in = sdpvar(1,obj.N_pred);  

            % Optimization Variables - real numbers
            p_g_in = sdpvar(1,obj.N_pred); % TODO: later rewrite power flow balance to get rid of those parameters -> express as function of p_b... -> write constraints as min max or so
            p_g_out = sdpvar(1,obj.N_pred);
            p_b_ch = sdpvar(1,obj.N_pred);
            p_b_dch = sdpvar(1,obj.N_pred);

            % Optimization variables - binary
            delta_b_ch = binvar(1,obj.N_pred);
            delta_b_dch = binvar(1,obj.N_pred);
            delta_g_in = binvar(1,obj.N_pred);
            delta_g_out = binvar(1,obj.N_pred);


            constraints = obj.computeConstraints(x1, p_in, p_g_in, p_g_out, p_b_ch, p_b_dch, delta_b_ch, delta_b_dch, delta_g_in, delta_g_out);
            cost = obj.computeCost(p_in, p_b_ch, p_b_dch, p_g_in);
            

            solver_settings = sdpsettings('solver','mosek','verbose',1);

            obj.controller = optimizer(constraints, cost, solver_settings, ...
                                       {x1, p_in}, ... % Input parameters
                                        {p_b_ch, p_b_dch, p_g_in}); % Output  - of optimization variables

        end

        function cost = computeCost(obj, p_in, p_b_ch, p_b_dch, p_g_in)
            u = [p_in - p_b_ch; p_in - p_b_dch; p_g_in];
            cost = u'*obj.R_cost*u;


        end

        function constraints = computeConstraints(obj, x1, p_in, p_g_in, p_g_out, p_b_ch, p_b_dch, delta_b_ch, delta_b_dch, delta_g_in, delta_g_out)
            constraints = [];
            delta_t = obj.T_s;
            minimal_battery_level = (1 - obj.DOD)*obj.E_bat;

            % power flow balance
            % p_in = p_g_out + p_b_ch + p_b_dch + p_g_in
            constraints = [constraints, p_in == p_g_out + p_b_ch - p_b_dch + p_g_in];


            % battery dynamics
            % x_i+1 = x_i + nu_ch*p_b_ch*delta_t + (1/nu_dch)*p_b_dch*delta_t - L_bat*x_i*delta_t

            x = [x1];

            for k = 1:obj.N_pred-1
                x_next = x(:,k) + obj.nu_ch*p_b_ch(k)*delta_t + (1/obj.nu_dch)*p_b_dch(k)*delta_t - obj.L_bat*x(:,k)*delta_t;
                constraints = [constraints, minimal_battery_level <= x_next <= obj.E_bat];
                x = [x, x_next];
            end


            % no charging and discharging at the same time
            constraints = [constraints, 0 <= p_b_ch <= obj.P_batconv_max*delta_b_ch];
            constraints = [constraints, -obj.P_batconv_max*delta_b_dch <= p_b_dch <= 0];
            constraints = [constraints, delta_b_ch + delta_b_dch <= 1];

            % no grid infeed and consumption at the same time
            constraints = [constraints, 0 <= p_g_out <= obj.P_gridcons_max*delta_g_out];
            constraints = [constraints, -obj.P_gridcons_max*delta_g_in <= p_g_in <= 0];
            constraints = [constraints, delta_g_in + delta_g_out <= 1];

            % not allowed to decharge battery directly into grid outlet
            constraints = [constraints, delta_b_dch + delta_g_out <= 1];

            % I one wants that it is not allowed to charge battery directly from grid - TODO: check if thats a good idea
            constraints = [constraints, delta_b_ch + delta_g_in <= 1];
            
            
        end
        
        function output = computeControlAction(obj, current_battery_energy, pv_forecast, load_forecast)
            % Führt die Optimierung aus und gibt den ersten Steuerinput zurück
            p_in = pv_forecast - load_forecast;
            u = obj.controller{current_battery_energy, p_in}; % jetzt übergebe ich noch alle fast alle optimization variabeln
            output = u;
        end
    end
end

