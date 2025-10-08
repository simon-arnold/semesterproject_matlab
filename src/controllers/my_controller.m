%close all
clc
clear

%% Parameter Setup
Ts = 15/60; % in hours (15 minutes)
N_pred = 24/Ts; % Prediction horizon: 24 hours in time steps
N_sim = 48/Ts; % Simulation time: 48 hours in time steps (2 days)

plot_simple_controller = true;

[pv_forecast, load_forecast, t_extended] = create_forecasts(N_pred, false);

%% MPC Parameter
R_cost = diag([100, 100, 2000]); 
nu_ch = 0.85;
nu_dch = 0.95;
L_bat = 0;
E_bat = 3;
DOD = 0.4;
P_batconv_max = 1.8;
P_gridcons_max = 30;

noise_options = struct(...
    'apply_noise', true, ...
    'pv_std', 0.3, ...    
    'load_std', 0.7 ...   
);

%% MPC Controller Initialization
mpc = MPC_Controller(24, N_pred, Ts, R_cost, nu_ch, nu_dch, L_bat, E_bat, DOD, P_batconv_max, P_gridcons_max);
simpleController = simple_controller(Ts, nu_ch, nu_dch, E_bat, DOD, P_batconv_max, P_gridcons_max);

x_initial = 2.5; % Initial battery capacity in kWh (must be > 1.8 kWh)

battery_energy_sim_MPC = zeros(1, N_sim+1);
p_b_ch_applied_MPC = zeros(1, N_sim);
p_b_dch_applied_MPC = zeros(1, N_sim);
p_g_in_applied_MPC = zeros(1, N_sim);
p_g_out_applied_MPC = zeros(1, N_sim);
p_net_applied_MPC = zeros(1, N_sim);
p_g_net_applied_MPC = zeros(1, N_sim);  

%for debugging
p_g_in_optimizer_MPC = zeros(1, N_sim);
p_g_out_optimizer_MPC = zeros(1, N_sim);

battery_energy_sim_MPC(1) = x_initial;

fprintf('Starting MPC Receding Horizon Simulation over %d time steps (%.1f hours)...\n', N_sim, N_sim*Ts);

for k = 1:N_sim

    if mod(k, 10) == 0 || k == 1 || k == N_sim
        fprintf('MPC: Time step %d/%d (%.2f h) - %.1f%% complete\n', k, N_sim, (k-1)*Ts, k/N_sim*100);
    end
    
    start_idx = k;
    end_idx = k + N_pred - 1;
    
    % Check if enough forecast data is available
    if end_idx > length(pv_forecast)
        fprintf('Warning: Not enough forecast data! Using available data.');
        end_idx = length(pv_forecast);
        current_N_pred = end_idx - start_idx + 1;
        
        pv_forecast_window = pv_forecast(start_idx:end_idx);
        load_forecast_window = load_forecast(start_idx:end_idx);
        
        % Fill missing data with last available values
        if current_N_pred < N_pred
            pv_forecast_window = [pv_forecast_window, ...
                                  repmat(pv_forecast_window(end), 1, N_pred - current_N_pred)];
            load_forecast_window = [load_forecast_window, ...
                                    repmat(load_forecast_window(end), 1, N_pred - current_N_pred)];
        end
    else
        pv_forecast_window = pv_forecast(start_idx:end_idx);
        load_forecast_window = load_forecast(start_idx:end_idx);
    end

    if noise_options.apply_noise

        [pv_forecast_window_noise, load_forecast_window_noise] = add_forecast_noise(pv_forecast_window, load_forecast_window, k, N_pred, Ts, noise_options);
        [p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt] = ...
            mpc.computeControlAction(battery_energy_sim_MPC(k), pv_forecast_window_noise, load_forecast_window_noise);
    
    else
        
        [p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt] = ...
            mpc.computeControlAction(battery_energy_sim_MPC(k), pv_forecast_window, load_forecast_window);
    end

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
battery_energy_sim_simple = zeros(1, N_sim+1);
p_b_ch_applied_simple = zeros(1, N_sim);
p_b_dch_applied_simple = zeros(1, N_sim);
p_g_in_applied_simple = zeros(1, N_sim);
p_g_out_applied_simple = zeros(1, N_sim);
p_net_applied_simple = zeros(1, N_sim);
p_g_net_applied_simple = zeros(1, N_sim);  

battery_energy_sim_simple(1) = x_initial;

for k = 1:N_sim

    if mod(k, 10) == 0 || k == 1 || k == N_sim
        fprintf('Simple Controller: Time step %d/%d (%.2f h) - %.1f%% complete\n', k, N_sim, (k-1)*Ts, k/N_sim*100);
    end
    
    [p_b_ch_simple, p_b_dch_simple] = ...
        simpleController.computeControlAction(battery_energy_sim_simple(k), ...
                                              pv_forecast(k), ...
                                              load_forecast(k));
    
    p_b_ch_applied_simple(k) = p_b_ch_simple;
    p_b_dch_applied_simple(k) = p_b_dch_simple;

    p_net_applied_simple(k) = pv_forecast(k) - load_forecast(k);
    p_g_net_applied_simple(k) = p_net_applied_simple(k) - p_b_ch_applied_simple(k) - p_b_dch_applied_simple(k);

    p_g_in_applied_simple(k) = min(0, p_g_net_applied_simple(k));   % Negative = Consumption
    p_g_out_applied_simple(k) = max(0, p_g_net_applied_simple(k));  % Positive = Feed-in

    battery_energy_sim_simple(k+1) = battery_energy_sim_simple(k) + ...
                              nu_ch * p_b_ch_applied_simple(k) * Ts + ...
                              (1/nu_dch) * p_b_dch_applied_simple(k) * Ts - ...
                              L_bat * battery_energy_sim_simple(k) * Ts;
    
    % fprintf('SOC = %.2f kWh, p_bat = %.2f kW\n', battery_energy_sim_MPC(k+1), ...
    %         p_b_ch_applied_MPC(k) + p_b_dch_applied_MPC(k));
    
    
end


%% First optimization for comparison (entire horizon at once)
fprintf('Performing comparison optimization over entire horizon for checking if managed to solve the problem\n');
[p_b_ch_opt_full, p_b_dch_opt_full, p_g_in_opt_full, p_g_out_opt_full] = ...
    mpc.computeControlAction(x_initial, pv_forecast(1:N_pred), load_forecast(1:N_pred));

disp('Battery charging power:');
disp(p_b_ch_opt_full(1:5));
disp('Battery discharging power:'); 
disp(p_b_dch_opt_full(1:5));
disp('Grid consumption power:');
disp(p_g_in_opt_full(1:5));

forecasts_struct = struct(...
    'pv', pv_forecast, ...
    'load', load_forecast, ...
    't', t_extended ...
    );

results_struct = struct(...
    'p_b_ch_applied_MPC', p_b_ch_applied_MPC, ...
    'p_b_dch_applied_MPC', p_b_dch_applied_MPC, ...
    'p_g_in_applied_MPC', p_g_in_applied_MPC, ...
    'p_g_out_applied_MPC', p_g_out_applied_MPC, ...
    'p_net_applied_MPC', p_net_applied_MPC, ...
    'p_g_net_applied_MPC', p_g_net_applied_MPC, ...
    'battery_energy_sim_MPC', battery_energy_sim_MPC, ...
    'p_b_ch_applied_simple', p_b_ch_applied_simple, ...
    'p_b_dch_applied_simple', p_b_dch_applied_simple, ...
    'p_g_in_applied_simple', p_g_in_applied_simple, ...
    'p_g_out_applied_simple', p_g_out_applied_simple, ...
    'p_net_applied_simple', p_net_applied_simple, ...
    'p_g_net_applied_simple', p_g_net_applied_simple, ...
    'battery_energy_sim_simple', battery_energy_sim_simple ...
);

model_parameters = struct(...
    'E_bat', E_bat, ...
    'DOD', DOD ...
);

plot_options = struct(...
    'N_sim', N_sim, ...
    'N_pred', N_pred, ...
    'Ts', Ts, ...
    'plot_simple_controller', plot_simple_controller ...
);

plot_controller_results(forecasts_struct, results_struct, model_parameters, plot_options);