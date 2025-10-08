function plot_controller_results(forecasts, results, model_parameters, options )
    %TODO: Add description
    %% Plotting the results

    % Time vector for simulation
    t_sim = (0:options.N_sim-1) * options.Ts;
    t_full = (0:options.N_pred-1) * options.Ts;

    % Figure 2: Extended forecasts
    figure;
    subplot(2,1,1);
    plot(forecasts.t, forecasts.pv, 'LineWidth', 2, 'Color', [1 0.5 0]);
    xlabel('Time [h]');
    ylabel('PV Power [kW]');
    title('Extended PV Forecast (3 days)');
    grid on;
    xlim([0 max(forecasts.t)]);

    subplot(2,1,2);
    plot(forecasts.t, forecasts.load, 'LineWidth', 2, 'Color', 'blue');
    xlabel('Time [h]');
    ylabel('Load [kW]');
    title('Extended Load Forecast (3 days)');
    grid on;
    xlim([0 max(forecasts.t)]);

    % Figure 3: System overview (Battery control, PV production and load with Grid-Net)
    figure;

    % Subplot 1: Battery control (Charging/Discharging combined)
    subplot(3,1,1);
    plot(t_sim, results.p_b_ch_applied + results.p_b_dch_applied, 'LineWidth', 2, 'Color', 'g', 'DisplayName', 'Net Battery Control');
    xlabel('Time [h]');
    ylabel('Power [kW]');
    title('Battery Control');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);

    % Subplot 2: PV production
    subplot(3,1,2);
    % Extract PV data for simulation period
    pv_forecast = forecasts.pv(1:options.N_sim);
    plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'PV Production');
    xlabel('Time [h]');
    ylabel('PV Power [kW]');
    title('PV Production');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);

    % Subplot 3: Load and Grid-Net-Power
    subplot(3,1,3);
    % Extract load data for simulation period
    load_forecast = forecasts.load(1:options.N_sim);
    plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', 'blue', 'DisplayName', 'Load');
    hold on;
    plot(t_sim, results.p_g_net_applied, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net-Power');
    xlabel('Time [h]');
    ylabel('Power [kW]');
    title('Load and Grid-Net-Power (pos=Feed-in, neg=Consumption)');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);
    ylim([min([load_forecast, results.p_g_net_applied])*1.1, max([load_forecast, results.p_g_net_applied])*1.1]);

    % Figure 4: Receding Horizon Simulation Results
    figure;

    % Subplot 1: Battery charging power
    subplot(5,1,1);
    plot(t_sim, results.p_b_ch_applied, 'LineWidth', 2, 'Color', 'green');
    xlabel('Time [h]');
    ylabel('[kW]');
    title('Battery Charging Power');
    grid on;
    xlim([0 max(t_sim)]);

    % Subplot 2: Battery discharging power
    subplot(5,1,2);
    plot(t_sim, results.p_b_dch_applied, 'LineWidth', 2, 'Color', 'red');
    xlabel('Time [h]');
    ylabel('[kW]');
    title('Battery Discharging Power');
    grid on;
    xlim([0 max(t_sim)]);

    % Subplot 3: Grid consumption power
    subplot(5,1,3);
    plot(t_sim, results.p_g_in_applied, 'LineWidth', 2, 'Color', 'blue');
    xlabel('Time [h]');
    ylabel('[kW]');
    title('Grid Consumption Power');
    grid on;
    xlim([0 max(t_sim)]);

    % Subplot 4: Battery energy (State of Charge)
    subplot(5,1,4);
    plot((0:options.N_sim)*options.Ts, results.battery_energy_sim/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'y');
    hold on;
    yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
    xlabel('Time [h]');
    ylabel('[%]');
    title('Battery Energy Evolution (State of Charge)');
    legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);
    ylim([min(results.battery_energy_sim)*0.9/model_parameters.E_bat, 1.1]);

    % Subplot 5: Grid-Net-Power (from energy balance)
    subplot(5,1,5);
    plot(t_sim, results.p_g_net_applied, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net (Energy Balance)');
    xlabel('Time [h]');
    ylabel('[kW]');
    title('Grid-Net-Power:');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);
    ylim([min(results.p_g_net_applied)*1.1, max(results.p_g_net_applied)*1.1]);

    % Figure 5: Grid-Power Breakdown
    figure;

    subplot(3,1,1);
    plot(t_sim, results.p_net_applied, 'LineWidth', 2, 'Color', 'magenta', 'DisplayName', 'Net Power (PV-Load)');
    hold on;
    plot(t_sim, results.p_b_ch_applied + results.p_b_dch_applied, 'LineWidth', 2, 'Color', 'black', 'DisplayName', 'Battery Control');
    xlabel('Time [h]');
    ylabel('Power [kW]');
    title('Net Power and Battery Control');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);

    subplot(3,1,2);
    plot(t_sim, results.p_g_net_applied, 'LineWidth', 3, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net (Energy Balance)');
    hold on;
    plot(t_sim, results.p_g_out_applied, 'LineWidth', 2, 'Color', 'green', 'DisplayName', 'Grid-Out (Optimizer)');
    plot(t_sim, results.p_g_in_applied, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Grid-In (Optimizer)');
    yline(0, 'k--', 'Alpha', 0.5);
    xlabel('Time [h]');
    ylabel('Grid-Power [kW]');
    title('Grid-Power Comparison: Energy Balance vs. Optimizer Variables');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);

    subplot(3,1,3);
    plot(t_sim, results.p_g_out_energy_balance, 'LineWidth', 2, 'Color', [0.5 1 0.5], 'DisplayName', 'Feed-in (from p\_g\_net)');
    hold on;
    plot(t_sim, results.p_g_in_energy_balance, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'Consumption (from p\_g\_net)');
    plot(t_sim, results.p_g_out_applied, '--', 'LineWidth', 1.5, 'Color', 'green', 'DisplayName', 'Feed-in (Optimizer)');
    plot(t_sim, results.p_g_in_applied, '--', 'LineWidth', 1.5, 'Color', 'red', 'DisplayName', 'Consumption (Optimizer)');
    xlabel('Time [h]');
    ylabel('Grid-Power [kW]');
    title('Breakdown: Feed-in vs. Consumption');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);

end