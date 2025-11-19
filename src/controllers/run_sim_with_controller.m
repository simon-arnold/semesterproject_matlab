close all
clc
clear

%% ========================================================================
%  ENERGY MANAGEMENT SIMULATION - Main Script
%  ========================================================================
%  This script demonstrates the use of the EnergyManagementSimulation cl    ass
%  to simulate and compare MPC and simple controller strategies.
%  ========================================================================

%% Simulation Parameters
Ts = 15/60; % Time step in hours (15 minutes)
N_pred = 48; % Prediction horizon: 24 hours in time steps
% TODO: es gibt auhc kaum einen unterschied zwischen forecast von 32 zu 48


%N_sim = 48/Ts; % Simulation time: 48 hours in time steps (2 days)
x_initial = 2.5; % Initial battery capacity in kWh (must be > Bat. Cap. * (1-max DOD) kWh)

start_date = datetime(2019, 3, 22, 0, 0, 0); 
end_date = datetime(2019, 3, 25, 0, 0, 0);   

N_sim = ceil(hours(end_date - start_date) / Ts);  
disp(['Calculated N_sim: ', num2str(N_sim)]);


%% Battery Parameters
battery_params = struct(...
    'nu_ch', 0.93, ...          % Charging efficiency
    'nu_dch', 0.93, ...         % Discharging efficiency
    'L_bat', 0, ...             % Battery loss factor
    'E_bat', 5.100, ...             % Battery capacity in kWh
    'DOD', 0.6, ...             % Depth of discharge
    'P_batconv_max', 2000, ... % Maximum battery converter power
    'P_gridcons_max', 30, ...    % Maximum grid consumption power
    'nu_pv', 0.96 ...
);

%% MPC Cost Matrix
R_cost = diag([100, 100, 2000]);

%% Noise Options
noise_options = struct(...
    'apply_noise', false, ...
    'growing_over_time', true, ...
    'pv_std', 3.5, ...    
    'load_std', 6.5 ...   
);

% Alternative noise configurations (uncomment to use):
% Low noise:
%   'apply_noise', true, 'growing_over_time', false, 
%   'pv_std', 0.2, 'load_std', 0.7

% Medium noise:
%   'apply_noise', true, 'growing_over_time', true, 
%   'pv_std', 1.3, 'load_std', 3

% High noise (current setting):
%   'apply_noise', true, 'growing_over_time', true, 
%   'pv_std', 3.5, 'load_std', 6.5

%% Peak Shaving Metrics Options
peakshaving_metrics_options = struct(...
    'p_ref', 1.5, ...                      % Reference power in kW
    'plot_peakshaving_metrics', true ...   % Enable plotting
);

%% Plot Options
plot_options = struct(...
    'N_sim', N_sim, ...
    'N_pred', N_pred, ...
    'Ts', Ts, ...
    'plot_simple_controller', true ...
);

%% Initialize Controllers
mpc_controller = MPC_Controller(...
    24, N_pred, Ts, R_cost, ...
    battery_params.nu_ch, battery_params.nu_dch, ...
    battery_params.L_bat, battery_params.E_bat, ...
    battery_params.DOD, battery_params.P_batconv_max, ...
    battery_params.P_gridcons_max, battery_params.nu_pv);

simple_controller_obj = simple_controller(...
    Ts, battery_params.nu_ch, battery_params.nu_dch, ...
    battery_params.E_bat, battery_params.DOD, ...
    battery_params.P_batconv_max, battery_params.P_gridcons_max, ...
    battery_params.nu_pv);

%% Create Simulation Parameters Structure
sim_params = struct(...
    'Ts', Ts, ...
    'N_pred', N_pred, ...
    'N_sim', N_sim, ...
    'x_initial', x_initial, ...
    'mpc_controller', mpc_controller, ...
    'simple_controller', simple_controller_obj ...
);

%% ========================================================================
%  MAIN SIMULATION
%  ========================================================================

fprintf('=================================================================\n');
fprintf('  Energy Management Simulation\n');
fprintf('=================================================================\n');
fprintf('Simulation horizon: %.1f hours (%d time steps)\n', N_sim*Ts, N_sim);
fprintf('Prediction horizon: %.1f hours (%d time steps)\n', N_pred*Ts, N_pred);
fprintf('Time step: %.1f minutes\n', Ts*60);
fprintf('Noise enabled: %s\n', string(noise_options.apply_noise));
fprintf('=================================================================\n\n');

% Initialize simulation object
sim = EnergyManagementSimulation(...
    sim_params, battery_params, noise_options, ...
    'UseNNPredictor', true, ...
    'PredictionHorizon', N_pred, ...
    'UseRealData', true, ...
    'StartDate', start_date, ...
    'EndDate', end_date);
 

% Run full horizon optimization for debugging
% TODO: Rausfinden was diese funktion genau macht und für was ich die brauche

% sim.runFullHorizonOptimization();

% Run MPC simulation using the NN predictor with real data
sim.runMPCSimulationWithNN();

% Run Simple controller simulation with real data
if plot_options.plot_simple_controller
    sim.runSimpleSimulation();
end

%% ========================================================================
%  RESULTS AND PLOTTING
%  ========================================================================

fprintf('=================================================================\n');
fprintf('  Generating Results\n');
fprintf('=================================================================\n');

% Get results from simulation
Correct_Load_PV_data = sim.getCorrectLoadPV();
results_struct = sim.getResultsStruct();
model_parameters = sim.getModelParameters();
disp("Forecasts Struct:");
disp(Correct_Load_PV_data);
disp("Results Struct:");
disp(results_struct);

% Plot results
plot_controller_results(Correct_Load_PV_data, results_struct, model_parameters, plot_options);

% Calculate and plot peak shaving metrics
calculate_peakshaving_metrics(...
    results_struct.p_g_net_applied_MPC, ...
    results_struct.p_g_net_applied_simple, ...
    peakshaving_metrics_options);

fprintf('\nSimulation completed successfully!\n');