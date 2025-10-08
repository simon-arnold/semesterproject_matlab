close all
clc
clear

%% Parameter Setup
Ts = 15/60; % in hours (15 minutes)
N_pred = 24/Ts; % Prediction horizon: 24 hours in time steps
N_sim = 48/Ts; % Simulation time: 48 hours in time steps (2 days)

[dummy_pv_extended, dummy_load_extended, t_extended] = create_forecasts(N_pred, false);

%% MPC Parameter
R_cost = diag([100, 100, 2000]); 
nu_ch = 0.85;
nu_dch = 0.95;
L_bat = 0;
E_bat = 3;
DOD = 0.4;
P_batconv_max = 1.8;
P_gridcons_max = 30;

%% MPC Controller Initialization
mpc = MPC_Controller(24, N_pred, Ts, R_cost, nu_ch, nu_dch, L_bat, E_bat, DOD, P_batconv_max, P_gridcons_max);

%%Simulation
x_initial = 2.5; % Initial battery capacity in kWh (must be > 1.8 kWh)

% Initialize storage arrays for simulation
battery_energy_sim_MPC = zeros(1, N_sim+1);
p_b_ch_applied_MPC = zeros(1, N_sim);
p_b_dch_applied_MPC = zeros(1, N_sim);
p_g_in_applied_MPC = zeros(1, N_sim);
p_g_out_applied_MPC = zeros(1, N_sim);
p_net_applied_MPC = zeros(1, N_sim);
p_g_net_applied_MPC = zeros(1, N_sim);  % Net grid power calculated from energy balance

%for debugging
p_g_in_optimizer_MPC = zeros(1, N_sim);
p_g_out_optimizer_MPC = zeros(1, N_sim);

battery_energy_sim_MPC(1) = x_initial;

fprintf('Starting MPC Receding Horizon Simulation over %d time steps (%.1f hours)...\n', N_sim, N_sim*Ts);

for k = 1:N_sim

    if mod(k, 10) == 0 || k == 1 || k == N_sim
        fprintf('Time step %d/%d (%.2f h) - %.1f%% complete\n', k, N_sim, (k-1)*Ts, k/N_sim*100);
    end
    
    start_idx = k;
    end_idx = k + N_pred - 1;
    
    % Check if enough forecast data is available
    if end_idx > length(dummy_pv_extended)
        fprintf('Warning: Not enough forecast data! Using available data.');
        end_idx = length(dummy_pv_extended);
        current_N_pred = end_idx - start_idx + 1;
        
        pv_forecast_window = dummy_pv_extended(start_idx:end_idx);
        load_forecast_window = dummy_load_extended(start_idx:end_idx);
        
        % Fill missing data with last available values
        if current_N_pred < N_pred
            pv_forecast_window = [pv_forecast_window, ...
                                  repmat(pv_forecast_window(end), 1, N_pred - current_N_pred)];
            load_forecast_window = [load_forecast_window, ...
                                    repmat(load_forecast_window(end), 1, N_pred - current_N_pred)];
        end
    else
        pv_forecast_window = dummy_pv_extended(start_idx:end_idx);
        load_forecast_window = dummy_load_extended(start_idx:end_idx);
    end
    
    % Perform MPC optimization
    [p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt] = ...
        mpc.computeControlAction(battery_energy_sim_MPC(k), pv_forecast_window, load_forecast_window);
    
    p_b_ch_applied_MPC(k) = p_b_ch_opt(1);
    p_b_dch_applied_MPC(k) = p_b_dch_opt(1);
    p_g_in_optimizer_MPC(k) = p_g_in_opt(1);
    p_g_out_optimizer_MPC(k) = p_g_out_opt(1);

    p_net_applied_MPC(k) = pv_forecast_window(1) - load_forecast_window(1);
    p_g_net_applied_MPC(k) = p_net_applied_MPC(k) - p_b_ch_applied_MPC(k) - p_b_dch_applied_MPC(k);

    p_g_in_applied_MPC(k) = min(0, p_g_net_applied_MPC(k));   % Negative = Consumption
    p_g_out_applied_MPC(k) = max(0, p_g_net_applied_MPC(k));  % Positive = Feed-in

    battery_energy_sim_MPC(k+1) = battery_energy_sim_MPC(k) + ...
                              nu_ch * p_b_ch_applied_MPC(k) * Ts + ...
                              (1/nu_dch) * p_b_dch_applied_MPC(k) * Ts - ...
                              L_bat * battery_energy_sim_MPC(k) * Ts;
    
    % fprintf('SOC = %.2f kWh, p_bat = %.2f kW\n', battery_energy_sim_MPC(k+1), ...
    %         p_b_ch_applied_MPC(k) + p_b_dch_applied_MPC(k));
    
    
end

fprintf('MPC Receding Horizon Simulation completed.\n\n');

fprintf('Starting simple controller Simulation over %d time steps (%.1f hours)...\n', N_sim, N_sim*Ts);



%% First optimization for comparison (entire horizon at once)
fprintf('Performing comparison optimization over entire horizon for checking if managed to solve the problem\n');
[p_b_ch_opt_full, p_b_dch_opt_full, p_g_in_opt_full, p_g_out_opt_full] = ...
    mpc.computeControlAction(x_initial, dummy_pv_extended(1:N_pred), dummy_load_extended(1:N_pred));

disp('Battery charging power:');
disp(p_b_ch_opt_full(1:5));
disp('Battery discharging power:'); 
disp(p_b_dch_opt_full(1:5));
disp('Grid consumption power:');
disp(p_g_in_opt_full(1:5));

forecasts_struct = struct(...
    'pv', dummy_pv_extended, ...
    'load', dummy_load_extended, ...
    't', t_extended ...
    );

results_struct = struct(...
    'p_b_ch_applied', p_b_ch_applied_MPC, ...
    'p_b_dch_applied', p_b_dch_applied_MPC, ...
    'p_g_in_applied', p_g_in_applied_MPC, ...
    'p_g_out_applied', p_g_out_applied_MPC, ...
    'p_net_applied', p_net_applied_MPC, ...
    'p_g_net_applied', p_g_net_applied_MPC, ...
    'battery_energy_sim', battery_energy_sim_MPC ...
);

model_parameters = struct(...
    'E_bat', E_bat, ...
    'DOD', DOD ...
);

plot_options = struct(...
    'N_sim', N_sim, ...
    'N_pred', N_pred, ...
    'Ts', Ts ...
);

plot_controller_results(forecasts_struct, results_struct, model_parameters, plot_options);

% Summary of results
fprintf('\n=== MPC RECEDING HORIZON SIMULATION SUMMARY ===\n');
fprintf('Simulation duration: %.1f hours (%d time steps of %.0f min)\n', N_sim*Ts, N_sim, Ts*60);
fprintf('Prediction horizon: %.1f hours (%d time steps)\n', N_pred*Ts, N_pred);
fprintf('Initial battery energy: %.2f kWh\n', battery_energy_sim_MPC(1));
fprintf('Final battery energy: %.2f kWh\n', battery_energy_sim_MPC(end));
fprintf('Minimum battery energy: %.2f kWh\n', min(battery_energy_sim_MPC));
fprintf('Maximum battery energy: %.2f kWh\n', max(battery_energy_sim_MPC));
fprintf('Total battery charging: %.2f kWh\n', sum(p_b_ch_applied_MPC) * Ts);
fprintf('Total battery discharging: %.2f kWh\n', abs(sum(p_b_dch_applied_MPC)) * Ts);
fprintf('Total grid consumption: %.2f kWh\n', abs(sum(p_g_in_applied_MPC)) * Ts);
fprintf('Total grid feed-in: %.2f kWh\n', sum(p_g_out_applied_MPC) * Ts);
fprintf('Grid-Net-Energy: %.2f kWh (pos=Feed-in, neg=Consumption)\n', sum(p_g_net_applied_MPC) * Ts);
fprintf('Average Grid-Net-Power: %.3f kW\n', mean(p_g_net_applied_MPC));
fprintf('Max grid feed-in: %.2f kW\n', max(p_g_net_applied_MPC));
fprintf('Max grid consumption: %.2f kW\n', min(p_g_net_applied_MPC));
fprintf('======================================================\n\n');

