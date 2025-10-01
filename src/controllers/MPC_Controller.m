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

            disp('MPC Controller initialized.');
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
            disp('Constraints formulated.');
            cost = obj.computeCost(p_in, p_b_ch, p_b_dch, p_g_in);
            disp('Cost function formulated.');

            solver_settings = sdpsettings('solver','mosek','verbose',1);

            obj.controller = optimizer(constraints, cost, solver_settings, ...
                                       {x1, p_in}, ... % Input parameters
                                        {p_b_ch, p_b_dch, p_g_in, p_g_out}); % Output  - of optimization variables
            disp('YALMIP optimizer created.');

        end

        function cost = computeCost(obj, p_in, p_b_ch, p_b_dch, p_g_in)
            cost = 0;
            for k = 1:obj.N_pred
                u = [p_in(k) - p_b_ch(k); p_in(k) - p_b_dch(k); p_g_in(k)];
                cost = cost + u'*obj.R_cost*u;
            end
        end

        function constraints = computeConstraints(obj, x1, p_in, p_g_in, p_g_out, p_b_ch, p_b_dch, delta_b_ch, delta_b_dch, delta_g_in, delta_g_out)
            constraints = [];
            delta_t = obj.T_s;
            minimal_battery_level = (1 - obj.DOD)*obj.E_bat;

            % power flow balance
            % p_in = p_g_out + p_b_ch + p_b_dch + p_g_in
            constraints = [constraints, p_in == p_g_out + p_b_ch + p_b_dch + p_g_in];
            disp('Power flow balance constraint added.');


            % battery dynamics
            % x_i+1 = x_i + nu_ch*p_b_ch*delta_t + (1/nu_dch)*p_b_dch*delta_t - L_bat*x_i*delta_t

            x = [x1];

            for k = 1:obj.N_pred-1
                x_next = x(:,k) + obj.nu_ch*p_b_ch(k)*delta_t + (1/obj.nu_dch)*p_b_dch(k)*delta_t - obj.L_bat*x(:,k)*delta_t;
                constraints = [constraints, minimal_battery_level <= x_next <= obj.E_bat];
                x = [x, x_next];
                
            end
            disp('Battery dynamics constraints added.');


            % no charging and discharging at the same time
            constraints = [constraints, 0 <= p_b_ch <= obj.P_batconv_max*delta_b_ch];
            constraints = [constraints, -obj.P_batconv_max*delta_b_dch <= p_b_dch <= 0];
            constraints = [constraints, delta_b_ch + delta_b_dch <= 1];
            disp('No simultaneous charge/discharge constraints added.');

            % no grid infeed and consumption at the same time
            constraints = [constraints, 0 <= p_g_out <= obj.P_gridcons_max*delta_g_out];
            constraints = [constraints, -obj.P_gridcons_max*delta_g_in <= p_g_in <= 0];
            constraints = [constraints, delta_g_in + delta_g_out <= 1];
            disp('No simultaneous grid infeed/consumption constraints added.');

            % not allowed to decharge battery directly into grid outlet
            constraints = [constraints, delta_b_dch + delta_g_out <= 1];
            disp('No direct battery to grid outlet constraint added.');

            % I one wants that it is not allowed to charge battery directly from grid - TODO: check if thats a good idea
            constraints = [constraints, delta_b_ch + delta_g_in <= 1];
            disp('No direct grid to battery charging constraint added.');
            
        end

        function [p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt] = computeControlAction(obj, current_battery_energy, pv_forecast, load_forecast)
            % Führt die Optimierung aus und gibt die optimalen Steuerinputs zurück
            p_in = pv_forecast - load_forecast;
            
            % Debug-Informationen
            disp(['Aktuelle Batterieenergie: ', num2str(current_battery_energy)]);
            disp(['Min/Max p_in: ', num2str(min(p_in)), ' / ', num2str(max(p_in))]);
            disp(['Batteriekapazität: ', num2str(obj.E_bat)]);
            disp(['Minimaler Batterielevel: ', num2str((1-obj.DOD)*obj.E_bat)]);
            
            [u, diagnostics] = obj.controller{current_battery_energy, p_in}; 
            
            % Prüfe Solver-Status
            if diagnostics ~= 0
                disp(['Solver-Fehler! Diagnostics code: ', num2str(diagnostics)]);
                if diagnostics == 1
                    disp('Problem ist infeasible (keine zulässige Lösung)');
                elseif diagnostics == 2
                    disp('Problem ist unbounded');
                elseif diagnostics == 3
                    disp('Numerische Probleme');
                else
                    disp('Unbekannter Solver-Fehler');
                end
            end
            
            % Extrahiere die einzelnen Datenreihen aus dem cell array
            p_b_ch_opt = u{1};   % Batterieladeleistung
            p_b_dch_opt = u{2};  % Batterieentladeleistung  
            p_g_in_opt = u{3};   % Netzbezugsleistung
            p_g_out_opt = u{4};  % Netzeinspeiseleistung
        end
    end
end

