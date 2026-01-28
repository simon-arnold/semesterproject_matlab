classdef MPC_Controller < handle
    properties
        % MPC Parameters
        T_pred      % Prediction Time/horizon
        N_pred      % Prediction Horizon steps
        T_s         % Sampling Time/delta t [h]
        nx = 1; 

        R_cost
        
        % System Parameters
        % Battery System
        nu_ch
        nu_dch      % charging & decharging efficiencies
        L_bat       % battery loss
        E_bat       % battery capacity
        DOD         % Depth of Discharge

        % PV System
        nu_pv       % PV efficiency

        % Electricity Cost 
        use_electricity_price
        use_peak_pricing
        high_sell_price
        high_buy_price
        low_buy_price
        low_sell_price
        peak_price

        % Max Transmission Power
        P_batconv_max
        P_gridcons_max

        % YALMIP Optimizer
        controller  % Optimizer Object

        % Plotting params for single prediciton horizon plots
        MPC_plotting_params
        plotting_k = []
    end
    
    methods
        function obj = MPC_Controller(T_pred, N_pred, T_s, R_cost, ...
                                      nu_ch, nu_dch, L_bat, E_bat, ...
                                      DOD, P_batconv_max, P_gridcons_max, ...
                                      nu_pv, electricity_cost_struct, MPC_plotting_params)
            % Konstruktor: System und MPC Parameter initialisieren
            obj.T_pred = T_pred;
            obj.N_pred = N_pred;
            disp("TS = " + T_s);
            obj.T_s = T_s;
            obj.R_cost = R_cost;
            obj.nu_ch = nu_ch;
            obj.nu_dch = nu_dch;
            obj.L_bat = L_bat;
            obj.E_bat = E_bat;
            obj.DOD = DOD;
            obj.P_batconv_max = P_batconv_max;
            obj.P_gridcons_max = P_gridcons_max;
            obj.nu_pv = nu_pv;


            %Electricity_cost
            obj.use_electricity_price = electricity_cost_struct.use_electricity_price;
            obj.use_peak_pricing = electricity_cost_struct.use_peak_pricing;
            obj.high_sell_price = electricity_cost_struct.high_sell_price;
            obj.high_buy_price = electricity_cost_struct.high_buy_price;
            obj.low_buy_price = electricity_cost_struct.low_buy_price;
            obj.low_sell_price = electricity_cost_struct.low_sell_price;
            obj.peak_price = electricity_cost_struct.peak_price;

            % MPC Plotting params
            obj.MPC_plotting_params = MPC_plotting_params;

            start_date = MPC_plotting_params.start_date;
            list_of_MPC_horizons = MPC_plotting_params.list_of_MPC_horizons;

            if MPC_plotting_params.num_MPC_horizons ~= length(list_of_MPC_horizons)
                error('Number of MPC horizons does not match length of list_of_MPC_horizons');
            end

            

            % Find the index k for plotting
            for i = 1:MPC_plotting_params.num_MPC_horizons
                horizon_time = list_of_MPC_horizons(i);
                k_horizon = round(hours(horizon_time - start_date) / T_s) + 1; % +1 for MATLAB indexing
                obj.plotting_k = [obj.plotting_k, k_horizon];
            end

            % Optimierungsproblem aufbauen
            obj.constructOptimizationProblem();

            disp('MPC Controller initialized.');
        end
        
        function constructOptimizationProblem(obj)
            
            % Parameters
            x1 = sdpvar(obj.nx,1);     
            p_in = sdpvar(1,obj.N_pred + 1);
            price_buy_vector = sdpvar(1,obj.N_pred + 1);   % Kaufpreise für jeden Zeitschritt
            price_sell_vector = sdpvar(1,obj.N_pred + 1);  % Verkaufspreise für jeden Zeitschritt

            % Optimization Variables - real numbers
            p_g_in = sdpvar(1,obj.N_pred + 1); % TODO: later rewrite power flow balance to get rid of those parameters -> express as function of p_b... -> write constraints as min max or so
            p_g_out = sdpvar(1,obj.N_pred + 1);
            p_b_ch = sdpvar(1,obj.N_pred + 1);
            p_b_dch = sdpvar(1,obj.N_pred + 1);

            % Optimization variables - binary
            delta_b_ch = binvar(1,obj.N_pred + 1);
            delta_b_dch = binvar(1,obj.N_pred + 1);
            delta_g_in = binvar(1,obj.N_pred + 1);
            delta_g_out = binvar(1,obj.N_pred + 1);

            
            [constraints, x] = obj.computeConstraints(x1, p_in, p_g_in, p_g_out, p_b_ch, p_b_dch, delta_b_ch, delta_b_dch, delta_g_in, delta_g_out);
            disp('Constraints formulated.');
            cost = obj.computeCost(p_in, p_b_ch, p_b_dch, p_g_in, p_g_out, price_buy_vector, price_sell_vector, x);
            disp('Cost function formulated.');

            solver_settings = sdpsettings('solver','mosek','verbose',1);

            obj.controller = optimizer(constraints, cost, solver_settings, ...
                                       {x1, p_in, price_buy_vector, price_sell_vector}, ... % Input parameters
                                        {p_b_ch, p_b_dch, p_g_in, p_g_out}); % Output  - of optimization variables
            disp('YALMIP optimizer created.');

        end

        function cost = computeCost(obj, p_in, p_b_ch, p_b_dch, p_g_in, p_g_out, price_buy_vector, price_sell_vector, x)
            cost = 0;
            discount_factor = 1

            if obj.use_electricity_price
                for k = 1:(obj.N_pred + 1)
                    % Verwende zeitabhängige Preise aus den übergebenen Vektoren
                    % Kosten für Netzbezug (p_g_in < 0, daher negativ) und Einspeisung (p_g_in > 0, daher positiv)
                    % Wichtig: Mit T_s multiplizieren um Energie (kWh) zu erhalten: Leistung (kW) * Zeit (h) = Energie (kWh)
                    cost = cost + discount_factor^(k-1) * (price_buy_vector(k) * (-p_g_in(k)) - price_sell_vector(k) * p_g_out(k)) * obj.T_s;
                end

                % % Add peak price cost (monthly)
                if obj.use_peak_pricing
                    max_grid_consumption = -min(p_g_in);
                    cost = cost + obj.peak_price * max_grid_consumption * obj.T_s * (obj.N_pred + 1) / (24*30); % Approx. monthly factor
                end
                
                % add minimal reward for filled battery
                % % TODO: how do i tune this epsilon ?
                
                % epsilon = 7e-3;
                % epsilon = 3e-3; % works well for house A
                epsilon = 5e-3; % works well for house E
                % epsilon = 1e-3;
                cost = cost - epsilon * sum(x); 

                % TODO: other cost could be difference between two timesteps of of battery charging & battery discharging power


                
            else
                for k = 1:(obj.N_pred + 1)
                    u = [p_in(k) - p_b_ch(k); p_in(k) - p_b_dch(k); p_g_in(k)];
                    cost = cost + u'*obj.R_cost*u;
                end
            end
            
        end

        function [constraints, x] = computeConstraints(obj, x1, p_in, p_g_in, p_g_out, p_b_ch, p_b_dch, delta_b_ch, delta_b_dch, delta_g_in, delta_g_out)
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

            for k = 1:obj.N_pred
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

        function [p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt] = computeControlAction(obj, current_battery_energy, current_pv, current_load, pv_forecast, load_forecast, current_time_minutes, sim_k, load_window_ground_truth)
            % Führt die Optimierung aus und gibt die optimalen Steuerinputs zurück
            % current_time_minutes: Aktuelle Tageszeit in Minuten seit Mitternacht (0-1439) (in Minutes)
            
            pv_curr_predict = [current_pv, pv_forecast];    
            load_curr_predict = [current_load, load_forecast]; 

            p_in_current = current_pv * obj.nu_pv - current_load;
            p_in_forecast = pv_forecast * obj.nu_pv - load_forecast;
            p_in = [p_in_current, p_in_forecast]; 

            % Berechne zeitabhängige Strompreise für jeden Zeitschritt
            % Momentan noch die gleichen Hoch und niedertarifszeiten, unabhängig von deem Wochentag
            price_buy_vector = zeros(1, obj.N_pred + 1);
            price_sell_vector = zeros(1, obj.N_pred + 1);
            
            for k = 1:(obj.N_pred + 1)
                % Berechne Zeit für diesen Zeitschritt in Minuten
                time_minutes = mod(current_time_minutes + (k-1)*obj.T_s*60, 24*60);
                
                % Bestimme ob Hoch- oder Niedertarif (Beispiel: Hochtarif 7:00-20:00)
                if time_minutes >= 7*60 && time_minutes < 20*60
                    % Hochtarif
                    price_buy_vector(k) = obj.high_buy_price;
                    price_sell_vector(k) = obj.high_sell_price;
                else
                    % Niedertarif
                    price_buy_vector(k) = obj.low_buy_price;
                    price_sell_vector(k) = obj.low_sell_price;
                end
            end


            
            [u, diagnostics] = obj.controller{current_battery_energy, p_in, price_buy_vector, price_sell_vector}; 

            % disp("u length: " + num2str(length(u)));
            
            % Prüfe Solver-Status
            if diagnostics ~= 0
               warning ("MPC Solver returned with status: " + num2str(diagnostics));
               disp(yalmiperror(diagnostics));
               error('MPC Optimization failed.');
                
            end
            
            % Extrahiere die einzelnen Datenreihen aus dem cell array
            p_b_ch_opt = u{1};   % Batterieladeleistung
            p_b_dch_opt = u{2};  % Batterieentladeleistung  
            p_g_in_opt = u{3};   % Netzbezugsleistung
            p_g_out_opt = u{4};  % Netzeinspeiseleistung

            if ismember(sim_k, obj.plotting_k)
                current_datetime = obj.MPC_plotting_params.list_of_MPC_horizons(find(obj.plotting_k == sim_k));
                obj.plot_current_prediction_window(sim_k, p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt, current_battery_energy, u, p_in, load_curr_predict, pv_curr_predict, current_datetime, load_window_ground_truth);
            end
            
        end

        function plot_current_prediction_window(obj, k, p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt, current_battery_energy, u, p_in, load_curr_predict, pv_curr_predict, current_datetime, load_window_ground_truth)
            % Plotte die Ergebnisse der aktuellen Vorhersageperiode über das MPC Prediction Window
            disp("Load window ground truth:");
            disp(load_window_ground_truth);
            disp("Load current predict(1):");
            disp(load_curr_predict(1));
            disp("load window ground truth shape:");
            disp(size(load_window_ground_truth));
            disp("load current predict shape:");
            disp(size(load_curr_predict(1)));
            % Stelle sicher, dass load_window_ground_truth als Row-Vektor vorliegt
            load_ground_truth = [load_curr_predict(1), reshape(load_window_ground_truth, 1, [])];
            
            % Zeitvektor für Prediction Horizon erstellen
            if obj.MPC_plotting_params.plot_with_current_datetime
                % Erstelle datetime Array beginnend bei current_datetime
                t_pred = current_datetime + hours((0:obj.N_pred) * obj.T_s);
            else
                % Relative Zeit in Stunden ab aktuellem Zeitpunkt
                t_pred = (0:obj.N_pred) * obj.T_s;
            end
            
            % Batterieleistung netto (positiv=Laden, negativ=Entladen)
            battery_net = p_b_ch_opt + p_b_dch_opt;
            
            % Netzleistung netto (positiv=Einspeisung, negativ=Bezug)
            grid_net = p_g_out_opt + p_g_in_opt;
            
            % Batteriezustand berechnen (aus u extrahieren falls verfügbar)
            %TODO: add here the battery state of the Optimizer
            x_trajectory = [current_battery_energy, zeros(1, obj.N_pred)];
            for i = 1:obj.N_pred
                x_trajectory(i+1) = x_trajectory(i) + obj.nu_ch*p_b_ch_opt(i)*obj.T_s + ...
                                    (1/obj.nu_dch)*p_b_dch_opt(i)*obj.T_s - ...
                                    obj.L_bat*x_trajectory(i)*obj.T_s;
            end
            
            % Erstelle Figure
            figure('Name', sprintf('MPC Prediction Window at k=%d', k), 'NumberTitle', 'off');
            sgtitle(sprintf('MPC Prediction Window at Timestep k=%d', k));
            
            % Subplot 1: Eingangssignal p_in (PV - Load)
            ax1 = subplot(3,1,1);
            plot(t_pred, pv_curr_predict, 'LineWidth', 2, 'Color', [1 0.6 0], 'DisplayName', 'PV Production');
            plot(t_pred, load_ground_truth, 'LineWidth', 2, 'Color', [0.2 0.4 0.8], 'LineStyle', '--', 'DisplayName', 'Load Ground Truth');
            hold on;
            plot(t_pred, load_curr_predict, 'LineWidth', 2, 'Color', [1 0 0], 'DisplayName', 'Load Predicted');
            plot(t_pred, p_in, 'LineWidth', 2, 'Color', [0.4 0.9 0.4], 'DisplayName', 'Net Power (PV-Load)');
            xlabel('Time [h]');
            ylabel('Power [kW]');
            title('PV Production vs. Load');
            legend('Location', 'best');
            grid on;
            xlim([t_pred(1) t_pred(end)]);
            
            % Subplot 2: Optimale Leistungsverteilung (Batterie und Netz)
            ax2 = subplot(3,1,2);
            plot(t_pred, battery_net, 'LineWidth', 2.5, 'Color', [0.8 0.2 0.2], 'DisplayName', 'Battery Power');
            hold on;
            plot(t_pred, grid_net, 'LineWidth', 2.5, 'Color', [0.2 0.6 0.8], 'DisplayName', 'Grid Power');
            ylabel('Power [kW]');
            xlabel('Time [h]');
            title('Optimal Power Distribution (pos=Charge/Sell, neg=Discharge/Buy)');
            legend('Location', 'best');
            grid on;
            xlim([t_pred(1) t_pred(end)]);
            
            % Subplot 3: Batteriezustand (SOC)
            ax3 = subplot(3,1,3);
            plot(t_pred, x_trajectory/obj.E_bat * 100, 'LineWidth', 2.5, 'Color', 'black', 'DisplayName', 'Predicted SOC');
            hold on;
            yline((1-obj.DOD)*100, '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
            yline(100, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
            xlabel('Time [h]');
            ylabel('SOC [%]');
            title('Predicted Battery State of Charge');
            legend('Location', 'best');
            grid on;
            xlim([t_pred(1) t_pred(end)]);
            ylim([min(x_trajectory/obj.E_bat * 100)*0.95, 105]);
            
            % Synchronisiere x-Achsen
            linkaxes([ax1, ax2, ax3], 'x');

            % error('debug stop'); 

        end
    end
end

