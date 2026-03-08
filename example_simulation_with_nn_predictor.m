%% Example: Energy Management Simulation with NN Predictor and Real Data
% This script demonstrates how to use the EnergyManagementSimulation class
% with the NNPredictor and real data from dfE_300s.mat

clear; clc; close all;

% Add necessary paths
addpath(genpath('src'));
addpath(genpath('predictor'));

%% 1. Define Simulation Period
% Set the start and end date for the simulation
% Make sure these dates are within the available data range in dfE_300s.mat

start_date = datetime(2018, 1, 1, 0, 0, 0);  % Example: January 1, 2018
end_date = datetime(2018, 1, 7, 23, 45, 0);  % Example: 7 days later

fprintf('=== Simulation Configuration ===\n');
fprintf('Start Date: %s\n', datestr(start_date));
fprintf('End Date: %s\n', datestr(end_date));
fprintf('Duration: %.1f days\n', days(end_date - start_date));
fprintf('================================\n\n');

%% 2. Define Battery Parameters
battery_params = struct(...
    'nu_ch', 0.95, ...          % Charging efficiency
    'nu_dch', 0.95, ...         % Discharging efficiency
    'L_bat', 0.0001, ...        % Battery loss factor
    'E_bat', 10, ...            % Battery capacity [kWh]
    'DOD', 0.1, ...             % Depth of discharge
    'P_bat_max', 5);            % Maximum battery power [kW]

%% 3. Define Simulation Parameters
Ts = 0.25;  % Time step [hours] = 15 minutes
N_pred = 24;  % Prediction horizon (24 * 15min = 6 hours)
prediction_horizon_nn = 24;  % NN predictor horizon (must be 16, 24, 32, or 48)

% Calculate simulation horizon based on date range
% This will be overridden when real data is loaded
time_diff_hours = hours(end_date - start_date);
N_sim_estimated = ceil(time_diff_hours / Ts);

% Initial battery state [kWh]
x_initial = battery_params.E_bat * (1 - battery_params.DOD) / 2;

%% 4. Initialize Controllers

% MPC Controller
mpc_controller = MPC_Controller(...
    Ts, ...
    N_pred, ...
    battery_params.nu_ch, ...
    battery_params.nu_dch, ...
    battery_params.L_bat, ...
    battery_params.E_bat, ...
    battery_params.DOD, ...
    battery_params.P_bat_max);

% Simple Controller
simple_controller = simple_controller(...
    battery_params.nu_ch, ...
    battery_params.nu_dch, ...
    battery_params.L_bat, ...
    battery_params.E_bat, ...
    battery_params.DOD, ...
    battery_params.P_bat_max);

%% 5. Configure Noise Options
noise_opts = struct(...
    'apply_noise', false, ...   % Set to true to add forecast noise
    'noise_std_pv', 0.1, ...
    'noise_std_load', 0.05);

%% 6. Create sim_params struct
sim_params = struct(...
    'Ts', Ts, ...
    'N_pred', N_pred, ...
    'N_sim', N_sim_estimated, ...  % Will be updated when real data is loaded
    'x_initial', x_initial, ...
    'mpc_controller', mpc_controller, ...
    'simple_controller', simple_controller);

%% 7. Create Simulation Object with NN Predictor and Real Data

fprintf('\n=== Creating Simulation Object ===\n');

% Create simulation with NN predictor enabled and real data
sim = EnergyManagementSimulation(...
    sim_params, ...
    battery_params, ...
    noise_opts, ...
    'UseNNPredictor', true, ...           % Enable NN predictor
    'PredictionHorizon', prediction_horizon_nn, ...  % NN horizon
    'UseRealData', true, ...              % Load real data
    'StartDate', start_date, ...          % Simulation start date
    'EndDate', end_date);                 % Simulation end date

fprintf('Simulation object created successfully!\n');
fprintf('Actual N_sim: %d timesteps\n', sim.N_sim);
fprintf('==================================\n\n');

%% 8. Run MPC Simulation with NN Predictor

fprintf('\n=== Running MPC Simulation with NN Predictor ===\n');
try
    sim.runMPCSimulationWithNN();
    fprintf('MPC simulation with NN predictor completed successfully!\n');
catch ME
    fprintf('Error during MPC simulation: %s\n', ME.message);
    fprintf('Stack trace:\n');
    for i = 1:length(ME.stack)
        fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
    end
end

%% 9. Optional: Run Simple Controller for Comparison
% Note: Simple controller doesn't use NN predictor, uses standard forecasts

fprintf('\n=== Running Simple Controller Simulation (for comparison) ===\n');
try
    sim.runSimpleSimulation();
    fprintf('Simple controller simulation completed successfully!\n');
catch ME
    fprintf('Error during simple simulation: %s\n', ME.message);
end

%% 10. Get Results and Plot

fprintf('\n=== Generating Plots ===\n');

% Get results
results = sim.getResultsStruct();
forecasts = sim.getForecastsStruct();
model_params = sim.getModelParameters();

% Plot results (assuming you have the plot_results function)
try
    plot_results(results, forecasts, model_params, Ts, N_sim_estimated);
    fprintf('Plots generated successfully!\n');
catch ME
    fprintf('Note: Could not generate plots. Error: %s\n', ME.message);
    fprintf('You can manually plot the results from the ''results'' struct.\n');
end

%% 11. Display Summary Statistics

fprintf('\n=== Simulation Summary ===\n');
fprintf('MPC Controller:\n');
fprintf('  Total grid consumption: %.2f kWh\n', sum(abs(results.p_g_in_applied_MPC)) * Ts);
fprintf('  Total grid feed-in: %.2f kWh\n', sum(results.p_g_out_applied_MPC) * Ts);
fprintf('  Battery cycles: %.2f\n', sum(results.p_b_ch_applied_MPC) * Ts / battery_params.E_bat);
fprintf('  Final battery energy: %.2f kWh\n', results.battery_energy_sim_MPC(end));

fprintf('\nSimple Controller:\n');
fprintf('  Total grid consumption: %.2f kWh\n', sum(abs(results.p_g_in_applied_simple)) * Ts);
fprintf('  Total grid feed-in: %.2f kWh\n', sum(results.p_g_out_applied_simple) * Ts);
fprintf('  Battery cycles: %.2f\n', sum(results.p_b_ch_applied_simple) * Ts / battery_params.E_bat);
fprintf('  Final battery energy: %.2f kWh\n', results.battery_energy_sim_simple(end));
fprintf('=========================\n\n');

fprintf('Simulation completed! Results are available in the ''results'' variable.\n');
