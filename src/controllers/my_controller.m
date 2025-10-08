%close all
clc
clear

%% Parameter Setup
Ts = 15/60; % in hours (15 minutes)
N_pred = 24/Ts; % Prediction horizon: 24 hours in time steps
N_sim = 48/Ts; % Simulation time: 48 hours in time steps (2 days)

[dummy_pv_extended, dummy_load_extended, t_extended] = create_forecasts(N_pred, true);

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

%% Receding Horizon Simulation
x_current = 2.5; % Initial battery capacity in kWh (must be > 1.8 kWh)

% Initialize storage arrays for simulation
battery_energy_sim = zeros(1, N_sim+1);
p_b_ch_applied = zeros(1, N_sim);
p_b_dch_applied = zeros(1, N_sim);
p_g_in_applied = zeros(1, N_sim);
p_g_out_applied = zeros(1, N_sim);
p_net_applied = zeros(1, N_sim);
p_g_net_applied = zeros(1, N_sim);  % Net grid power calculated from energy balance

battery_energy_sim(1) = x_current;

fprintf('Starting Receding Horizon Simulation over %d time steps (%.1f hours)...\n', N_sim, N_sim*Ts);

for k = 1:N_sim
    % Current time step
    fprintf('Time step %d/%d (%.2f h): ', k, N_sim, (k-1)*Ts);
    
    % Extract prediction window for current time step
    start_idx = k;
    end_idx = k + N_pred - 1;
    
    % Check if enough forecast data is available
    if end_idx > length(dummy_pv_extended)
        fprintf('Warning: Not enough forecast data! Using available data.\n');
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
        mpc.computeControlAction(battery_energy_sim(k), pv_forecast_window, load_forecast_window);
    
    % Apply only the first control command (Receding Horizon principle)
    p_b_ch_applied(k) = p_b_ch_opt(1);
    p_b_dch_applied(k) = p_b_dch_opt(1);
    p_g_in_applied(k) = p_g_in_opt(1);
    p_g_out_applied(k) = p_g_out_opt(1);
    
    % Calculate net power
    p_net_applied(k) = pv_forecast_window(1) - load_forecast_window(1);
    
    % Update battery state for next time step
    battery_energy_sim(k+1) = battery_energy_sim(k) + ...
                              nu_ch * p_b_ch_applied(k) * Ts + ...
                              (1/nu_dch) * p_b_dch_applied(k) * Ts - ...
                              L_bat * battery_energy_sim(k) * Ts;
    
    fprintf('SOC = %.2f kWh, p_bat = %.2f kW\n', battery_energy_sim(k+1), ...
            p_b_ch_applied(k) + p_b_dch_applied(k));
end

fprintf('Receding Horizon Simulation completed.\n\n');

%% Calculate actual grid powers from energy balance
% Calculate p_g_net based on energy balance: p_g_net = p_in - p_b_ch - p_b_dch
% Positive values = Grid feed-in, Negative values = Grid consumption
p_g_out_energy_balance = zeros(1, N_sim);
p_g_in_energy_balance = zeros(1, N_sim);

for k = 1:N_sim
    % Grid net power from energy balance (overwrites the preallocated array)
    p_g_net_applied(k) = p_net_applied(k) - p_b_ch_applied(k) - p_b_dch_applied(k);
    
    % Split into feed-in and consumption
    p_g_out_energy_balance(k) = max(0, p_g_net_applied(k));  % Positive = Feed-in
    p_g_in_energy_balance(k) = min(0, p_g_net_applied(k));   % Negative = Consumption
end

fprintf('=== GRID-POWER COMPARISON ===\n');
fprintf('Optimizer vs. Energy Balance for first 5 time steps:\n');
for i = 1:5
    fprintf('t=%d: Optimizer[in=%.3f, out=%.3f] vs. Energy Balance[net=%.3f, in=%.3f, out=%.3f]\n', ...
        i, p_g_in_applied(i), p_g_out_applied(i), p_g_net_applied(i), ...
        p_g_in_energy_balance(i), p_g_out_energy_balance(i));
end
fprintf('============================\n\n');

%% First optimization for comparison (entire horizon at once)
fprintf('Performing comparison optimization over entire horizon...\n');
[p_b_ch_opt_full, p_b_dch_opt_full, p_g_in_opt_full, p_g_out_opt_full] = ...
    mpc.computeControlAction(x_current, dummy_pv_extended(1:N_pred), dummy_load_extended(1:N_pred));

disp('First 5 optimal values (full horizon):');
disp('Battery charging power:');
disp(p_b_ch_opt_full(1:5));
disp('Battery discharging power:'); 
disp(p_b_dch_opt_full(1:5));
disp('Grid consumption power:');
disp(p_g_in_opt_full(1:5));

%% Plotting the results

% Time vector for simulation
t_sim = (0:N_sim-1) * Ts;
t_full = (0:N_pred-1) * Ts;

% Figure 2: Extended forecasts
figure;
subplot(2,1,1);
plot(t_extended, dummy_pv_extended, 'LineWidth', 2, 'Color', [1 0.5 0]);
xlabel('Time [h]');
ylabel('PV Power [kW]');
title('Extended PV Forecast (3 days)');
grid on;
xlim([0 max(t_extended)]);

subplot(2,1,2);
plot(t_extended, dummy_load_extended, 'LineWidth', 2, 'Color', 'blue');
xlabel('Time [h]');
ylabel('Load [kW]');
title('Extended Load Forecast (3 days)');
grid on;
xlim([0 max(t_extended)]);

% Figure 3: System overview (Battery control, PV production and load with Grid-Net)
figure;

% Subplot 1: Battery control (Charging/Discharging combined)
subplot(3,1,1);
plot(t_sim, p_b_ch_applied + p_b_dch_applied, 'LineWidth', 2, 'Color', 'g', 'DisplayName', 'Net Battery Control');
xlabel('Time [h]');
ylabel('Power [kW]');
title('Battery Control');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

% Subplot 2: PV production
subplot(3,1,2);
% Extract PV data for simulation period
pv_sim = dummy_pv_extended(1:N_sim);
plot(t_sim, pv_sim, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'PV Production');
xlabel('Time [h]');
ylabel('PV Power [kW]');
title('PV Production');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

% Subplot 3: Load and Grid-Net-Power
subplot(3,1,3);
% Extract load data for simulation period
load_sim = dummy_load_extended(1:N_sim);
plot(t_sim, load_sim, 'LineWidth', 2, 'Color', 'blue', 'DisplayName', 'Load');
hold on;
plot(t_sim, p_g_net_applied, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net-Power');
xlabel('Time [h]');
ylabel('Power [kW]');
title('Load and Grid-Net-Power (pos=Feed-in, neg=Consumption)');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);
ylim([min([load_sim, p_g_net_applied])*1.1, max([load_sim, p_g_net_applied])*1.1]);

% Figure 4: Receding Horizon Simulation Results
figure;

% Subplot 1: Battery charging power
subplot(5,1,1);
plot(t_sim, p_b_ch_applied, 'LineWidth', 2, 'Color', 'green');
xlabel('Time [h]');
ylabel('[kW]');
title('Battery Charging Power');
grid on;
xlim([0 max(t_sim)]);

% Subplot 2: Battery discharging power
subplot(5,1,2);
plot(t_sim, p_b_dch_applied, 'LineWidth', 2, 'Color', 'red');
xlabel('Time [h]');
ylabel('[kW]');
title('Battery Discharging Power');
grid on;
xlim([0 max(t_sim)]);

% Subplot 3: Grid consumption power
subplot(5,1,3);
plot(t_sim, p_g_in_applied, 'LineWidth', 2, 'Color', 'blue');
xlabel('Time [h]');
ylabel('[kW]');
title('Grid Consumption Power');
grid on;
xlim([0 max(t_sim)]);

% Subplot 4: Battery energy (State of Charge)
subplot(5,1,4);
plot((0:N_sim)*Ts, battery_energy_sim/E_bat, 'LineWidth', 2, 'Color', 'y');
hold on;
yline((1-DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
xlabel('Time [h]');
ylabel('[%]');
title('Battery Energy Evolution (State of Charge)');
legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
grid on;
xlim([0 max(t_sim)]);
ylim([min(battery_energy_sim)*0.9/E_bat, 1.1]);

% Subplot 5: Grid-Net-Power (from energy balance)
subplot(5,1,5);
plot(t_sim, p_g_net_applied, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net (Energy Balance)');
xlabel('Time [h]');
ylabel('[kW]');
title('Grid-Net-Power:');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);
ylim([min(p_g_net_applied)*1.1, max(p_g_net_applied)*1.1]);

% Figure 5: Grid-Power Breakdown
figure;

subplot(3,1,1);
plot(t_sim, p_net_applied, 'LineWidth', 2, 'Color', 'magenta', 'DisplayName', 'Net Power (PV-Load)');
hold on;
plot(t_sim, p_b_ch_applied + p_b_dch_applied, 'LineWidth', 2, 'Color', 'black', 'DisplayName', 'Battery Control');
xlabel('Time [h]');
ylabel('Power [kW]');
title('Net Power and Battery Control');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

subplot(3,1,2);
plot(t_sim, p_g_net_applied, 'LineWidth', 3, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net (Energy Balance)');
hold on;
plot(t_sim, p_g_out_applied, 'LineWidth', 2, 'Color', 'green', 'DisplayName', 'Grid-Out (Optimizer)');
plot(t_sim, p_g_in_applied, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Grid-In (Optimizer)');
yline(0, 'k--', 'Alpha', 0.5);
xlabel('Time [h]');
ylabel('Grid-Power [kW]');
title('Grid-Power Comparison: Energy Balance vs. Optimizer Variables');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

subplot(3,1,3);
plot(t_sim, p_g_out_energy_balance, 'LineWidth', 2, 'Color', [0.5 1 0.5], 'DisplayName', 'Feed-in (from p\_g\_net)');
hold on;
plot(t_sim, p_g_in_energy_balance, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'Consumption (from p\_g\_net)');
plot(t_sim, p_g_out_applied, '--', 'LineWidth', 1.5, 'Color', 'green', 'DisplayName', 'Feed-in (Optimizer)');
plot(t_sim, p_g_in_applied, '--', 'LineWidth', 1.5, 'Color', 'red', 'DisplayName', 'Consumption (Optimizer)');
xlabel('Time [h]');
ylabel('Grid-Power [kW]');
title('Breakdown: Feed-in vs. Consumption');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

%% Summary of results
fprintf('\n=== RECEDING HORIZON SIMULATION SUMMARY ===\n');
fprintf('Simulation duration: %.1f hours (%d time steps of %.0f min)\n', N_sim*Ts, N_sim, Ts*60);
fprintf('Prediction horizon: %.1f hours (%d time steps)\n', N_pred*Ts, N_pred);
fprintf('Initial battery energy: %.2f kWh\n', battery_energy_sim(1));
fprintf('Final battery energy: %.2f kWh\n', battery_energy_sim(end));
fprintf('Minimum battery energy: %.2f kWh\n', min(battery_energy_sim));
fprintf('Maximum battery energy: %.2f kWh\n', max(battery_energy_sim));
fprintf('Total battery charging: %.2f kWh\n', sum(p_b_ch_applied) * Ts);
fprintf('Total battery discharging: %.2f kWh\n', abs(sum(p_b_dch_applied)) * Ts);
fprintf('Total grid consumption: %.2f kWh\n', abs(sum(p_g_in_applied)) * Ts);
fprintf('Total grid feed-in: %.2f kWh\n', sum(p_g_out_applied) * Ts);
fprintf('\n--- ENERGY BALANCE-BASED GRID-POWER ---\n');
fprintf('Total grid consumption (Energy Balance): %.2f kWh\n', abs(sum(p_g_in_energy_balance)) * Ts);
fprintf('Total grid feed-in (Energy Balance): %.2f kWh\n', sum(p_g_out_energy_balance) * Ts);
fprintf('Grid-Net-Energy: %.2f kWh (pos=Feed-in, neg=Consumption)\n', sum(p_g_net_applied) * Ts);
fprintf('Average Grid-Net-Power: %.3f kW\n', mean(p_g_net_applied));
fprintf('Max grid feed-in: %.2f kW\n', max(p_g_net_applied));
fprintf('Max grid consumption: %.2f kW\n', min(p_g_net_applied));
fprintf('======================================================\n\n');

%% Demonstration: Comparison Optimizer vs. Energy Balance Grid-Powers
fprintf('=== COMPARISON: OPTIMIZER vs. ENERGY BALANCE ===\n');
fprintf('Example for first time step:\n');

% Show first time step of full horizon optimization
[p_b_ch_demo, p_b_dch_demo, p_g_in_opt_demo, p_g_out_opt_demo] = ...
    mpc.computeControlAction(x_current, dummy_pv_extended(1:N_pred), dummy_load_extended(1:N_pred));

% Calculate grid powers manually from energy balance
p_in_demo = dummy_pv_extended(1) - dummy_load_extended(1);
p_grid_net_demo = p_in_demo - p_b_ch_demo(1) - p_b_dch_demo(1);
p_g_out_manual = max(0, p_grid_net_demo);
p_g_in_manual = min(0, p_grid_net_demo);

fprintf('Optimizer Grid-Out: %.3f kW, Grid-In: %.3f kW\n', p_g_out_opt_demo(1), p_g_in_opt_demo(1));
fprintf('Energy Balance Grid-Out: %.3f kW, Grid-In: %.3f kW\n', p_g_out_manual, p_g_in_manual);
fprintf('Net Grid Power: %.3f kW (pos=Feed-in, neg=Consumption)\n', p_grid_net_demo);
fprintf('Energy Balance Check: p_in(%.3f) = p_g_out(%.3f) + p_b_ch(%.3f) + p_b_dch(%.3f) + p_g_in(%.3f) = %.3f\n', ...
    p_in_demo, p_g_out_manual, p_b_ch_demo(1), p_b_dch_demo(1), p_g_in_manual, ...
    p_g_out_manual + p_b_ch_demo(1) + p_b_dch_demo(1) + p_g_in_manual);
fprintf('==========================================\n\n');

%