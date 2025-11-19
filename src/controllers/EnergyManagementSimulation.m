classdef EnergyManagementSimulation < handle
    % EnergyManagementSimulation Class for structured energy management simulation
    %
    % This class encapsulates the simulation of energy management strategies
    % including MPC and simple controllers, managing forecasts, battery states,
    % and history for plotting.
    
    properties
        % Controllers
        mpc_controller
        simple_controller
        
        % Forecasts
        pv_forecast
        load_forecast
        t_extended
        
        % Predictor
        nn_predictor            % NNPredictor object (optional)
        use_nn_predictor        % Boolean flag
        
        % Real data
        real_data_table         % Table with real data (includes history before start_date!)
        real_data_times         % Time vector for real data
        start_date              % Simulation start date
        end_date                % Simulation end date
        sim_start_idx           % Index in real_data_table where actual simulation starts
        history_length          % Number of historical timesteps before start_date (for NN predictor)
        
        % Simulation parameters
        Ts              % Time step in hours
        N_pred          % Prediction horizon
        N_sim           % Simulation horizon
        x_initial       % Initial battery state
        
        % Battery parameters
        nu_ch           % Charging efficiency
        nu_dch          % Discharging efficiency
        L_bat           % Battery loss factor
        E_bat           % Battery capacity
        DOD             % Depth of discharge

        % PV parameters
        nu_pv           % PV efficiency
        
        % Noise options
        noise_options
        
        % History storage for MPC controller
        history_mpc
        
        % History storage for Simple controller
        history_simple
        
        % Current simulation state
        current_step_mpc
        current_step_simple
    end
    
    methods
        %% Constructor
        function obj = EnergyManagementSimulation(sim_params, battery_params, noise_opts, varargin)
            % Constructor with optional real data support
            %
            % Inputs:
            %   sim_params - Struct with simulation parameters
            %   battery_params - Struct with battery parameters
            %   noise_opts - Struct with noise options
            %   varargin - Optional name-value pairs:
            %              'UseNNPredictor', true/false - Use neural network predictor
            %              'PredictionHorizon', 16/24/32/48 - Horizon for NN predictor
            %              'StartDate', datetime - Start date for real data simulation
            %              'EndDate', datetime - End date for real data simulation
            %              'UseRealData', true/false - Load real data from file
            
            % Initialize simulation parameters
            obj.Ts = sim_params.Ts;
            obj.N_pred = sim_params.N_pred;
            obj.N_sim = sim_params.N_sim;
            obj.x_initial = sim_params.x_initial;
            
            % Initialize battery parameters
            obj.nu_ch = battery_params.nu_ch;
            obj.nu_dch = battery_params.nu_dch;
            obj.L_bat = battery_params.L_bat;
            obj.E_bat = battery_params.E_bat;
            obj.DOD = battery_params.DOD;
            obj.nu_pv = battery_params.nu_pv;
            
            % Initialize noise options
            obj.noise_options = noise_opts;
            
            % Initialize controllers
            obj.mpc_controller = sim_params.mpc_controller;
            obj.simple_controller = sim_params.simple_controller;
            
            % Parse optional arguments
            p = inputParser;
            addParameter(p, 'UseNNPredictor', false, @islogical);
            addParameter(p, 'PredictionHorizon', 24, @(x) ismember(x, [16, 24, 32, 48]));
            addParameter(p, 'StartDate', datetime('now'), @(x) isdatetime(x) || ischar(x) || isstring(x));
            addParameter(p, 'EndDate', datetime('now') + days(1), @(x) isdatetime(x) || ischar(x) || isstring(x));
            addParameter(p, 'UseRealData', false, @islogical);
            parse(p, varargin{:});
            
            obj.use_nn_predictor = p.Results.UseNNPredictor;
            obj.start_date = p.Results.StartDate;
            obj.end_date = p.Results.EndDate;
            
            % Initialize history length for NN predictor
            if obj.use_nn_predictor
                obj.history_length = 192;  % Default: 2*24*4 for 15-min intervals
            else
                obj.history_length = 0;
            end
            
            % Initialize predictor if requested
            if obj.use_nn_predictor
                fprintf('Initialisiere NNPredictor mit Horizont %d...\n', p.Results.PredictionHorizon);
                obj.nn_predictor = NNPredictor(p.Results.PredictionHorizon);
                obj.history_length = obj.nn_predictor.input_seq_len;  % Use actual input length from predictor
            else
                obj.nn_predictor = [];
            end
            
            % Load forecasts (only if not using real data)
            if ~p.Results.UseRealData
                [obj.pv_forecast, obj.load_forecast, obj.t_extended] = ...
                    create_forecasts(obj.N_pred, false);
            end
            
            % Load real data if requested (this may update N_sim)
            if p.Results.UseRealData
                obj.loadRealData(obj.start_date, obj.end_date);
            else
                obj.real_data_table = [];
                obj.real_data_times = [];
                obj.sim_start_idx = 1;
            end
            
            % Initialize history AFTER potentially updating N_sim
            obj.initializeHistory();
            
            % Initialize current steps
            obj.current_step_mpc = 1;
            obj.current_step_simple = 1;
        end
        
        %% Initialize History
        function initializeHistory(obj)
            % Initialize MPC history
            obj.history_mpc = struct(...
                'battery_energy', zeros(1, obj.N_sim+1), ...
                'p_b_ch', zeros(1, obj.N_sim), ...
                'p_b_dch', zeros(1, obj.N_sim), ...
                'p_g_in', zeros(1, obj.N_sim), ...
                'p_g_out', zeros(1, obj.N_sim), ...
                'p_net', zeros(1, obj.N_sim), ...
                'p_g_net', zeros(1, obj.N_sim), ...
                'p_g_in_optimizer', zeros(1, obj.N_sim), ...
                'p_g_out_optimizer', zeros(1, obj.N_sim));
            
            obj.history_mpc.battery_energy(1) = obj.x_initial;
            
            % Initialize Simple controller history
            obj.history_simple = struct(...
                'battery_energy', zeros(1, obj.N_sim+1), ...
                'p_b_ch', zeros(1, obj.N_sim), ...
                'p_b_dch', zeros(1, obj.N_sim), ...
                'p_g_in', zeros(1, obj.N_sim), ...
                'p_g_out', zeros(1, obj.N_sim), ...
                'p_net', zeros(1, obj.N_sim), ...
                'p_g_net', zeros(1, obj.N_sim));
            
            obj.history_simple.battery_energy(1) = obj.x_initial;
        end
        
        %% Get Forecast Window
        function [pv_window, load_window] = getForecastWindow(obj, k)
            % getForecastWindow Extracts forecast window for current time step
            %
            % Inputs:
            %   k - Current time step
            %
            % Outputs:
            %   pv_window - PV forecast window (with optional noise)
            %   load_window - Load forecast window (with optional noise)
            
            start_idx = k;
            end_idx = k + obj.N_pred - 1;
            
            % Check if enough forecast data is available
            if end_idx > length(obj.pv_forecast)
                fprintf('Warning: Not enough forecast data! Using available data.\n');
                end_idx = length(obj.pv_forecast);
                current_N_pred = end_idx - start_idx + 1;
                
                pv_window = obj.pv_forecast(start_idx:end_idx);
                load_window = obj.load_forecast(start_idx:end_idx);
                
                % Fill missing data with last available values
                if current_N_pred < obj.N_pred
                    pv_window = [pv_window, ...
                                repmat(pv_window(end), 1, obj.N_pred - current_N_pred)];
                    load_window = [load_window, ...
                                  repmat(load_window(end), 1, obj.N_pred - current_N_pred)];
                end
            else
                pv_window = obj.pv_forecast(start_idx:end_idx);
                load_window = obj.load_forecast(start_idx:end_idx);
            end
            
            % Add noise if enabled
            if obj.noise_options.apply_noise
                [pv_window, load_window] = add_forecast_noise(...
                    pv_window, load_window, k, obj.N_pred, obj.Ts, obj.noise_options);
            end
        end
        
        %% Apply MPC Controller
        function [p_b_ch, p_b_dch, p_g_in_opt, p_g_out_opt] = applyMPCController(obj, k)
            % applyMPCController Computes MPC control action for current time step
            %
            % Inputs:
            %   k - Current time step
            %
            % Outputs:
            %   p_b_ch - Battery charging power
            %   p_b_dch - Battery discharging power
            %   p_g_in_opt - Grid consumption (from optimizer)
            %   p_g_out_opt - Grid feed-in (from optimizer)
            
            % Get forecast window
            [pv_window, load_window] = obj.getForecastWindow(k);

            % Get current battery state
            battery_state = obj.history_mpc.battery_energy(k);

            % Get current PV and Load values (absolute index if real data available)
            if ~isempty(obj.real_data_table)
                abs_idx = obj.sim_start_idx + k - 1;
                pv_current = obj.real_data_table.PV_forecast(abs_idx) / 1000;  % W to kW
                load_current = obj.real_data_table.Load(abs_idx) / 1000;      % W to kW
            else
                pv_current = obj.pv_forecast(k);
                load_current = obj.load_forecast(k);
            end

            % Compute optimal control action (pass current values + forecast)
            [p_b_ch_opt, p_b_dch_opt, p_g_in_opt_full, p_g_out_opt_full] = ...
                obj.mpc_controller.computeControlAction(battery_state, pv_current, load_current, pv_window, load_window);
            
            % Extract first control action (receding horizon)
            p_b_ch = p_b_ch_opt(1);
            p_b_dch = p_b_dch_opt(1);
            p_g_in_opt = p_g_in_opt_full(1);
            p_g_out_opt = p_g_out_opt_full(1);
        end
        
        %% Apply Simple Controller
        function [p_b_ch, p_b_dch] = applySimpleController(obj, k)
            % applySimpleController Computes simple control action for current time step
            %
            % Inputs:
            %   k - Current time step
            %
            % Outputs:
            %   p_b_ch - Battery charging power
            %   p_b_dch - Battery discharging power
            
            % Get current battery state
            battery_state = obj.history_simple.battery_energy(k);
            
            % Get current PV and Load values
            if ~isempty(obj.real_data_table)
                % Use real data - calculate absolute index
                abs_idx = obj.sim_start_idx + k - 1;
                pv_current = obj.real_data_table.PV_forecast(abs_idx) / 1000;  % Convert W to kW
                load_current = obj.real_data_table.Load(abs_idx) / 1000;  % Convert W to kW
            else
                % Use generated forecasts (old behavior)
                pv_current = obj.pv_forecast(k);
                load_current = obj.load_forecast(k);
            end
            
            % Compute control action (simple controller only uses current values)
            [p_b_ch, p_b_dch] = ...
                obj.simple_controller.computeControlAction(...
                    battery_state, ...
                    pv_current, ...
                    load_current);
        end
        
        %% Update MPC State
        function updateMPCState(obj, k, p_b_ch, p_b_dch, p_g_in_opt, p_g_out_opt)
            % updateMPCState Updates battery state and history for MPC controller
            %
            % Inputs:
            %   k - Current time step
            %   p_b_ch - Applied battery charging power
            %   p_b_dch - Applied battery discharging power
            %   p_g_in_opt - Grid consumption from optimizer
            %   p_g_out_opt - Grid feed-in from optimizer
            
            % Store control actions
            obj.history_mpc.p_b_ch(k) = p_b_ch;
            obj.history_mpc.p_b_dch(k) = p_b_dch;
            obj.history_mpc.p_g_in_optimizer(k) = p_g_in_opt;
            obj.history_mpc.p_g_out_optimizer(k) = p_g_out_opt;
            
            % Get actual PV and Load values
            if ~isempty(obj.real_data_table)
                % Use real data - calculate absolute index
                abs_idx = obj.sim_start_idx + k - 1;
                pv_actual = obj.real_data_table.PV_forecast(abs_idx) / 1000;  % Convert W to kW
                load_actual = obj.real_data_table.Load(abs_idx) / 1000;  % Convert W to kW
            else
                % Use generated forecasts (old behavior)
                pv_actual = obj.pv_forecast(k);
                load_actual = obj.load_forecast(k);
            end
            
            % Calculate net power flows using actual values
            obj.history_mpc.p_net(k) = pv_actual * obj.nu_pv - load_actual;
            obj.history_mpc.p_g_net(k) = obj.history_mpc.p_net(k) - p_b_ch - p_b_dch;
            
            % Calculate actual grid power (not from optimizer)
            obj.history_mpc.p_g_in(k) = min(0, obj.history_mpc.p_g_net(k));   % Negative = Consumption
            obj.history_mpc.p_g_out(k) = max(0, obj.history_mpc.p_g_net(k));  % Positive = Feed-in
            
            % Update battery state
            obj.history_mpc.battery_energy(k+1) = obj.history_mpc.battery_energy(k) + ...
                obj.nu_ch * p_b_ch * obj.Ts + ...
                (1/obj.nu_dch) * p_b_dch * obj.Ts - ...
                obj.L_bat * obj.history_mpc.battery_energy(k) * obj.Ts;
        end
        
        %% Update Simple Controller State
        function updateSimpleState(obj, k, p_b_ch, p_b_dch)
            % updateSimpleState Updates battery state and history for simple controller
            %
            % Inputs:
            %   k - Current time step
            %   p_b_ch - Applied battery charging power
            %   p_b_dch - Applied battery discharging power
            
            % Store control actions
            obj.history_simple.p_b_ch(k) = p_b_ch;
            obj.history_simple.p_b_dch(k) = p_b_dch;
            
            % Get actual PV and Load values
            if ~isempty(obj.real_data_table)
                % Use real data - calculate absolute index
                abs_idx = obj.sim_start_idx + k - 1;
                pv_actual = obj.real_data_table.PV_forecast(abs_idx) / 1000;  % Convert W to kW
                load_actual = obj.real_data_table.Load(abs_idx) / 1000;  % Convert W to kW
            else
                % Use generated forecasts (old behavior)
                pv_actual = obj.pv_forecast(k);
                load_actual = obj.load_forecast(k);
            end
            
            % Calculate net power flows using actual values
            obj.history_simple.p_net(k) = pv_actual * obj.nu_pv - load_actual;
            obj.history_simple.p_g_net(k) = obj.history_simple.p_net(k) - p_b_ch - p_b_dch;
            
            % Calculate actual grid power
            obj.history_simple.p_g_in(k) = min(0, obj.history_simple.p_g_net(k));   % Negative = Consumption
            obj.history_simple.p_g_out(k) = max(0, obj.history_simple.p_g_net(k));  % Positive = Feed-in
            
            % Update battery state
            obj.history_simple.battery_energy(k+1) = obj.history_simple.battery_energy(k) + ...
                obj.nu_ch * p_b_ch * obj.Ts + ...
                (1/obj.nu_dch) * p_b_dch * obj.Ts - ...
                obj.L_bat * obj.history_simple.battery_energy(k) * obj.Ts;
        end
        
        %% Run MPC Simulation
        function runMPCSimulation(obj)
            % runMPCSimulation Runs the complete MPC simulation
            
            fprintf('Starting MPC Receding Horizon Simulation over %d time steps (%.1f hours)...\n', ...
                obj.N_sim, obj.N_sim*obj.Ts);
            
            for k = 1:obj.N_sim
                % Progress output
                if mod(k, 10) == 0 || k == 1 || k == obj.N_sim
                    fprintf('MPC: Time step %d/%d (%.2f h) - %.1f%% complete\n', ...
                        k, obj.N_sim, (k-1)*obj.Ts, k/obj.N_sim*100);
                end
                
                % Apply MPC controller
                [p_b_ch, p_b_dch, p_g_in_opt, p_g_out_opt] = obj.applyMPCController(k);
                
                % Update state and history
                obj.updateMPCState(k, p_b_ch, p_b_dch, p_g_in_opt, p_g_out_opt);
            end
            
            fprintf('MPC Receding Horizon Simulation completed.\n\n');
        end
        
        %% Run Simple Controller Simulation
        function runSimpleSimulation(obj)
            % runSimpleSimulation Runs the complete simple controller simulation
            
            fprintf('Starting simple controller Simulation over %d time steps (%.1f hours)...\n', ...
                obj.N_sim, obj.N_sim*obj.Ts);
            
            for k = 1:obj.N_sim
                % Progress output
                if mod(k, 10) == 0 || k == 1 || k == obj.N_sim
                    fprintf('Simple Controller: Time step %d/%d (%.2f h) - %.1f%% complete\n', ...
                        k, obj.N_sim, (k-1)*obj.Ts, k/obj.N_sim*100);
                end
                
                % Apply simple controller
                [p_b_ch, p_b_dch] = obj.applySimpleController(k);
                
                % Update state and history
                obj.updateSimpleState(k, p_b_ch, p_b_dch);
            end
            
            fprintf('Simple controller Simulation completed.\n\n');
        end
                
        %% Get Results for Plotting
        function results_struct = getResultsStruct(obj)
            % getResultsStruct Returns results in the format expected by plotting function

            %TODO: Convert those in only one per conection (liek add charge and discharge -> pay attention to keep Vorzeichenkkonvention)
            
            results_struct = struct(...
                'p_b_ch_applied_MPC', obj.history_mpc.p_b_ch, ...
                'p_b_dch_applied_MPC', obj.history_mpc.p_b_dch, ...
                'p_g_in_applied_MPC', obj.history_mpc.p_g_in, ...
                'p_g_out_applied_MPC', obj.history_mpc.p_g_out, ...
                'p_net_applied_MPC', obj.history_mpc.p_net, ...
                'p_g_net_applied_MPC', obj.history_mpc.p_g_net, ...
                'battery_energy_sim_MPC', obj.history_mpc.battery_energy, ...
                'p_b_ch_applied_simple', obj.history_simple.p_b_ch, ...
                'p_b_dch_applied_simple', obj.history_simple.p_b_dch, ...
                'p_g_in_applied_simple', obj.history_simple.p_g_in, ...
                'p_g_out_applied_simple', obj.history_simple.p_g_out, ...
                'p_net_applied_simple', obj.history_simple.p_net, ...
                'p_g_net_applied_simple', obj.history_simple.p_g_net, ...
                'battery_energy_sim_simple', obj.history_simple.battery_energy, ...
                'use_nn_predictor', obj.use_nn_predictor, ...
                'use_real_data', ~isempty(obj.real_data_table));
        end
        
        %% Get Forecasts for Plotting
        function load_pv_struct = getCorrectLoadPV(obj)
            % getForecastsStruct Returns forecasts in the format expected by plotting function
            
            if ~isempty(obj.real_data_table)
                % Use real data for plotting
                % Extract the simulation range (from sim_start_idx onwards)
                sim_indices = obj.sim_start_idx : (obj.sim_start_idx + obj.N_sim - 1);
                
                % Convert from W to kW for plotting
                pv_for_plot = obj.real_data_table.PV_forecast(sim_indices) / 1000;
                load_for_plot = obj.real_data_table.Load(sim_indices) / 1000;
                
                % Create time vector for plotting: use real datetime range
                t_for_plot = obj.real_data_times(sim_indices)';
                
                load_pv_struct = struct(...
                    'pv', pv_for_plot(:)', ...
                    'load', load_for_plot(:)', ...
                    't', t_for_plot, ...
                    'use_real_data', true, ...
                    'start_date', obj.start_date, ...
                    'end_date', obj.end_date);
            else
                % Use generated forecasts (old behavior)
                load_pv_struct = struct(...
                    'pv', obj.pv_forecast(1:obj.N_sim), ...
                    'load', obj.load_forecast(1:obj.N_sim), ...
                    't', obj.t_extended(1:obj.N_sim), ...
                    'use_real_data', false);
            end
        end
        
        %% Get Model Parameters for Plotting
        function model_params = getModelParameters(obj)
            % getModelParameters Returns model parameters for plotting
            
            model_params = struct(...
                'E_bat', obj.E_bat, ...
                'DOD', obj.DOD);
        end
        
        %% Run Full Horizon Optimization (for comparison)
        function runFullHorizonOptimization(obj)
            % runFullHorizonOptimization Runs optimization over entire horizon
            % (for debugging and comparison purposes)
            
            fprintf('Performing comparison optimization over entire horizon for checking if managed to solve the problem\n');
            
            % Get PV and Load forecasts depending on data source
            if ~isempty(obj.real_data_table)
                % Use real data for the first prediction horizon
                abs_start = obj.sim_start_idx;
                abs_end = abs_start + obj.N_pred - 1;
                
                if abs_end > height(obj.real_data_table)
                    fprintf('Warning: Not enough data for full horizon optimization. Skipping.\n');
                    return;
                end
                
                pv_test = obj.real_data_table.PV_forecast(abs_start:abs_end) / 1000;  % W to kW
                load_test = obj.real_data_table.Load(abs_start:abs_end) / 1000;  % W to kW
                
                % Ensure row vectors
                pv_test = pv_test(:)';
                load_test = load_test(:)';
            else
                % Use generated forecasts
                pv_test = obj.pv_forecast(1:obj.N_pred);
                load_test = obj.load_forecast(1:obj.N_pred);
            end
            
            [p_b_ch_opt_full, p_b_dch_opt_full, p_g_in_opt_full, p_g_out_opt_full] = ...
                obj.mpc_controller.computeControlAction(...
                    obj.x_initial, ...
                    pv_test, ...
                    load_test);
            
            disp('Battery charging power:');
            disp(p_b_ch_opt_full(1:5));
            disp('Battery discharging power:'); 
            disp(p_b_dch_opt_full(1:5));
            disp('Grid consumption power:');
            disp(p_g_in_opt_full(1:5));
        end
        
        %% Load Real Data
        function loadRealData(obj, start_date, end_date)
            % loadRealData Loads real data from MAT file for simulation
            %
            % Inputs:
            %   start_date - Start date for simulation
            %   end_date - End date for simulation
            
            fprintf('\n=== Loading Real Data ===\n');
            
            % Use helper function to load data (includes history for NN predictor)
            [obj.real_data_table, obj.real_data_times] = ...
                load_real_data(start_date, end_date, 'HistoryLength', obj.history_length, 'ForecastLength', obj.N_pred);

            disp('Real data table dimensions:');
            disp(size(obj.real_data_table));

            
            
            % Find the index where the actual simulation starts
            obj.sim_start_idx = find(obj.real_data_times >= start_date, 1, 'first');
            
            if isempty(obj.sim_start_idx)
                error('EnergyManagementSimulation:NoSimulationData', ...
                    'Keine Daten ab Startdatum gefunden!');
            end
            
            % Find the index where the actual simulation ends (at end_date, not including forecast extension)
            sim_end_idx = find(obj.real_data_times <= end_date, 1, 'last');
            
            if isempty(sim_end_idx) || sim_end_idx < obj.sim_start_idx
                error('EnergyManagementSimulation:InvalidSimulationRange', ...
                    'Ungültiger Simulationsbereich!');
            end
            
            % Update N_sim based on actual simulation range (NOT including forecast extension)
            obj.N_sim = sim_end_idx - obj.sim_start_idx + 1;
            
            fprintf('Simulation konfiguriert:\n');
            fprintf('  Table-Größe (inkl. Historie & Forecast): %d Zeitschritte\n', height(obj.real_data_table));
            fprintf('  Simulation startet bei Index: %d (Datum: %s)\n', obj.sim_start_idx, datestr(start_date));
            fprintf('  Simulation endet bei Index: %d (Datum: %s)\n', sim_end_idx, datestr(end_date));
            fprintf('  Simulation läuft über: %d Zeitschritte (%.2f Stunden)\n', ...
                obj.N_sim, obj.N_sim * obj.Ts);
            fprintf('  Verfügbare Forecast-Daten nach Simulation: %d Zeitschritte\n', ...
                height(obj.real_data_table) - sim_end_idx);
            fprintf('=========================\n\n');
        end
        
        %% Generate NN Forecast
        function forecast = generateNNForecast(obj, k)
            % generateNNForecast Generates forecast using NNPredictor
            %
            % Inputs:
            %   k - Current time step (relative to simulation start, i.e., 1-based from sim_start_idx)
            %
            % Output:
            %   forecast - Load forecast for prediction horizon
            
            % Input length for predictor
            input_len = obj.nn_predictor.input_seq_len;  % 192 timesteps
            
            % Calculate the absolute index in the real_data_table
            % k is relative to simulation start (sim_start_idx)
            absolute_k = obj.sim_start_idx + k - 1;
            
            % Calculate start index for history (need input_len history UP TO AND INCLUDING current step k)
            % NN should see [k-191 ... k] to predict [k+1 ... k+N_pred]
            start_idx = absolute_k - input_len + 1;
            
            if start_idx < 1
                error('EnergyManagementSimulation:InsufficientHistory', ...
                    'Not enough historical data for prediction at timestep %d. Need at least %d timesteps.', ...
                    k, input_len);
            end
            
            % Prepare features for predictor: Historie [start_idx ... absolute_k]
            % This gives the NN input_len timesteps of history UP TO AND INCLUDING current timestep
            features = prepare_predictor_features(obj.real_data_table, start_idx, input_len);

            % Print 10 Last timesteps of Load feature for debugging
            disp('Last 10 timesteps of Load feature for NN predictor (history up to k):');
            disp(features.Load(end-9:end));
            
            % Generate forecast
            forecast = obj.nn_predictor.predict(features);
            
            % Forecast is a vector of length prediction_horizon covering [k+1 ... k+N_pred]
            if mod(k, 50) == 1  % Only print occasionally to reduce output
                fprintf('Generated NN forecast for timestep %d (absolute idx: %d), history: [%d...%d], forecast: [%d...%d]\n', ...
                    k, absolute_k, start_idx, absolute_k, absolute_k+1, absolute_k+length(forecast));
            end
        end
        
        %% Get Forecast Window with NN Predictor
        function [pv_window, load_window] = getForecastWindowWithNN(obj, k)
            % getForecastWindowWithNN Get forecast using NN predictor and real PV data
            %
            % Inputs:
            %   k - Current time step (relative to simulation start)
            %
            % Outputs:
            %   pv_window - PV forecast window (from real data)
            %   load_window - Load forecast window (from NN predictor)

            % Absolute indices in real_data_table
            % Forecast window should contain the NEXT N_pred steps: [k+1 ... k+N_pred]
            % This is consistent with MPC which receives [current, forecast] = [k, k+1...k+N_pred]
            abs_start = obj.sim_start_idx + k; % start at NEXT timestep (k+1)
            abs_end = abs_start + obj.N_pred - 1;
            
            % Generate NN forecast for load (comes in W, convert to kW)
            if obj.use_nn_predictor
                load_window = obj.generateNNForecast(k);
            else
                load_window = obj.real_data_table.Load(abs_start:abs_end);
            end
            
            if length(load_window) ~= obj.N_pred
                error('EnergyManagementSimulation:NNForecastLengthMismatch', ...
                    'Forecast length does not match N_pred. Got %d, expected %d.', ...
                    length(load_window), obj.N_pred);
            end
            % Convert to row vector and from W to kW
            load_window = load_window(:)' / 1000;
            
           
            
            if abs_end > height(obj.real_data_table)
                error('EnergyManagementSimulation:InsufficientPVData', ...
                    'Nicht genug PV-Daten verfügbar. Benötigt Index %d bis %d, verfügbar bis %d.', ...
                    abs_start, abs_end, height(obj.real_data_table));
            end
            
            % Check if PV_forecast column exists
            pv_col = 'PV_forecast';
            if ~ismember(pv_col, obj.real_data_table.Properties.VariableNames)
                error('EnergyManagementSimulation:MissingPVColumn', ...
                    'Spalte "%s" nicht in real_data_table gefunden. Verfügbare Spalten: %s', ...
                    pv_col, strjoin(obj.real_data_table.Properties.VariableNames, ', '));
            end
            
            % Extract PV forecast window from real data and convert from W to kW
            pv_window = obj.real_data_table{abs_start:abs_end, pv_col};
            
            % Ensure row vector and convert W to kW
            pv_window = pv_window(:)' / 1000;

            disp('PV Window length:');
            disp(length(pv_window));
            disp('Load Window length:');
            disp(length(load_window));

            % Optional: Add noise if enabled (if you want to test noise on real PV forecast)
            if obj.noise_options.apply_noise
                [pv_window, load_window] = add_forecast_noise(...
                    pv_window, load_window, k, obj.N_pred, obj.Ts, obj.noise_options);
            end
        end
        
        %% Apply MPC Controller with NN Predictor
        function [p_b_ch, p_b_dch, p_g_in_opt, p_g_out_opt] = applyMPCControllerWithNN(obj, k)
            % applyMPCControllerWithNN Apply MPC with NN forecasts
            %
            % Inputs:
            %   k - Current time step
            %
            % Outputs:
            %   p_b_ch - Battery charging power
            %   p_b_dch - Battery discharging power
            %   p_g_in_opt - Grid consumption
            %   p_g_out_opt - Grid feed-in
            
            % Get forecast window using NN predictor
            [pv_window, load_window] = obj.getForecastWindowWithNN(k);  % Convert W to kW

            % disp('pv_window:')
            % disp(pv_window);
            % disp('load_window:')
            % disp(load_window);

            
            
            % Get current battery state
            battery_state = obj.history_mpc.battery_energy(k);
            disp('battery_state:')
            disp(battery_state);

            % Get current PV and Load values (absolute index if real data available)
            abs_idx = obj.sim_start_idx + k - 1;
            pv_current = obj.real_data_table.PV_forecast(abs_idx) / 1000;
            load_current = obj.real_data_table.Load(abs_idx) / 1000;
            
            % Compute optimal control action
            [p_b_ch_opt, p_b_dch_opt, p_g_in_opt_full, p_g_out_opt_full] = ...
                obj.mpc_controller.computeControlAction(battery_state, pv_current, load_current, pv_window, load_window);
            % disp('Computed optimal control actions:');
            % disp('p_b_ch_opt:');
            % disp(p_b_ch_opt);
            % disp('p_b_dch_opt:');
            % disp(p_b_dch_opt);
            % disp('p_g_in_opt_full:');
            % disp(p_g_in_opt_full);
            % disp('p_g_out_opt_full:');
            % disp(p_g_out_opt_full);

            % error('Debug stop after computing control actions with NN predictor.');

            disp("True Load Forecast")
            disp(obj.real_data_table.Load(abs_idx+1:abs_idx + obj.N_pred)' / 1000);
            
            % Extract first control action
            p_b_ch = p_b_ch_opt(1);
            p_b_dch = p_b_dch_opt(1);
            p_g_in_opt = p_g_in_opt_full(1);
            p_g_out_opt = p_g_out_opt_full(1);
        end
        
        %% Run MPC Simulation with NN Predictor
        function runMPCSimulationWithNN(obj)
            % runMPCSimulationWithNN Run MPC simulation using NN predictor
            
            
            if isempty(obj.real_data_table)
                error('EnergyManagementSimulation:NoRealData', ...
                    'Real data not loaded. Set UseRealData=true in constructor.');
            end
            
            % The simulation runs from timestep 1 to N_sim
            % Historical data is already loaded before sim_start_idx
            fprintf('Starting MPC Simulation with NN Predictor over %d time steps...\n', obj.N_sim);
            fprintf('Historical data available: %d timesteps before simulation start\n', obj.sim_start_idx - 1);
            fprintf('Simulation time range: %s to %s\n\n', ...
                datestr(obj.real_data_times(obj.sim_start_idx)), ...
                datestr(obj.real_data_times(end)));
            
            for k = 1:obj.N_sim
                % Progress output
                if mod(k, 10) == 0 || k == 1 || k == obj.N_sim
                    fprintf('MPC+NN: Time step %d/%d (%.2f h) - %.1f%% complete\n', ...
                        k, obj.N_sim, (k-1)*obj.Ts, k/obj.N_sim*100);
                end
                
                % Apply MPC controller with NN predictor
                [p_b_ch, p_b_dch, p_g_in_opt, p_g_out_opt] = obj.applyMPCControllerWithNN(k);
                
                % Update state and history
                obj.updateMPCState(k, p_b_ch, p_b_dch, p_g_in_opt, p_g_out_opt);
            end
            
            fprintf('MPC Simulation with NN Predictor completed.\n\n');
        end
    end
end
