function plot_controller_results(forecasts, results, model_parameters, options )
    %TODO: Add description
    %% Plotting the results

    % Time vector for simulation
    t_sim = (0:options.N_sim-1) * options.Ts;
    t_full = (0:options.N_pred-1) * options.Ts;

    % Figure 2: forecasts
    figure;
    subplot(2,1,1);
    plot(forecasts.t, forecasts.pv, 'LineWidth', 2, 'Color', [1 0.5 0]);
    xlabel('Time [h]');
    ylabel('PV Power [kW]');
    title('PV Forecast (3 days)');
    grid on;
    xlim([0 max(forecasts.t)]);

    subplot(2,1,2);
    plot(forecasts.t, forecasts.load, 'LineWidth', 2, 'Color', 'blue');
    xlabel('Time [h]');
    ylabel('Load [kW]');
    title('Load Forecast (3 days)');
    grid on;
    xlim([0 max(forecasts.t)]);


    % Figure 3: System overview (Battery control, PV production and load with Grid-Net)
    figure;
    sgtitle('MPC Controller Results');

    % Subplot 1: Battery control (Charging/Discharging combined)
    subplot(4,1,1);
    plot(t_sim, results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Net Battery Control');
    xlabel('Time [h]');
    ylabel('Power [kW]');
    title('Battery Control');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);
    ylim([min(results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC)*1.1, max(results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC)*1.1]);

    % Subplot 2: PV production
    subplot(4,1,2);
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
    subplot(4,1,3);
    % Extract load data for simulation period
    load_forecast = forecasts.load(1:options.N_sim);
    plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Load');
    hold on;
    plot(t_sim, -results.p_g_net_applied_MPC, 'LineWidth', 2, 'Color', 'blue', 'DisplayName', '-Grid-Net-Power');
    yline(0, 'k--', 'Alpha', 0.5);
    xlabel('Time [h]');
    ylabel('Power [kW]');
    title('Load and Grid-Net-Power (pos=Feed-in, neg=Consumption)');
    legend('Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);
    ylim([min([load_forecast, -results.p_g_net_applied_MPC])*1.1, max([load_forecast, -results.p_g_net_applied_MPC])*1.1]);

    subplot(4,1,4);
    plot((0:options.N_sim)*options.Ts, results.battery_energy_sim_MPC/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'y');
    hold on;
    yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
    xlabel('Time [h]');
    ylabel('[%]');
    title('Battery Energy Evolution (State of Charge)');
    legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);
    ylim([min(results.battery_energy_sim_MPC)*0.9/model_parameters.E_bat, 1.1]);

    % % Figure 4: Receding Horizon Simulation Results
    % figure;

    % % Subplot 1: Battery charging power
    % subplot(5,1,1);
    % plot(t_sim, results.p_b_ch_applied_MPC, 'LineWidth', 2, 'Color', 'green');
    % xlabel('Time [h]');
    % ylabel('[kW]');
    % title('Battery Charging Power');
    % grid on;
    % xlim([0 max(t_sim)]);

    % % Subplot 2: Battery discharging power
    % subplot(5,1,2);
    % plot(t_sim, results.p_b_dch_applied_MPC, 'LineWidth', 2, 'Color', 'red');
    % xlabel('Time [h]');
    % ylabel('[kW]');
    % title('Battery Discharging Power');
    % grid on;
    % xlim([0 max(t_sim)]);

    % % Subplot 3: Grid consumption power
    % subplot(5,1,3);
    % plot(t_sim, results.p_g_in_applied_MPC, 'LineWidth', 2, 'Color', 'blue');
    % xlabel('Time [h]');
    % ylabel('[kW]');
    % title('Grid Consumption Power');
    % grid on;
    % xlim([0 max(t_sim)]);

    % % Subplot 4: Battery energy (State of Charge)
    % subplot(5,1,4);
    % plot((0:options.N_sim)*options.Ts, results.battery_energy_sim_MPC/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'y');
    % hold on;
    % yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
    % xlabel('Time [h]');
    % ylabel('[%]');
    % title('Battery Energy Evolution (State of Charge)');
    % legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
    % grid on;
    % xlim([0 max(t_sim)]);
    % ylim([min(results.battery_energy_sim_MPC)*0.9/model_parameters.E_bat, 1.1]);

    % % Subplot 5: Grid-Net-Power (from energy balance)
    % subplot(5,1,5);
    % plot(t_sim, results.p_g_net_applied_MPC, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net (Energy Balance)');
    % xlabel('Time [h]');
    % ylabel('[kW]');
    % title('Grid-Net-Power:');
    % legend('Location', 'best');
    % grid on;
    % xlim([0 max(t_sim)]);
    % ylim([min(results.p_g_net_applied_MPC)*1.1, max(results.p_g_net_applied_MPC)*1.1]);

    % % Figure 5: Grid-Power Breakdown
    % figure;

    % subplot(3,1,1);
    % plot(t_sim, results.p_net_applied_MPC, 'LineWidth', 2, 'Color', 'magenta', 'DisplayName', 'Net Power (PV-Load)');
    % hold on;
    % plot(t_sim, results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC, 'LineWidth', 2, 'Color', 'black', 'DisplayName', 'Battery Control');
    % xlabel('Time [h]');
    % ylabel('Power [kW]');
    % title('Net Power and Battery Control');
    % legend('Location', 'best');
    % grid on;
    % xlim([0 max(t_sim)]);

    % subplot(3,1,2);
    % plot(t_sim, results.p_g_net_applied_MPC, 'LineWidth', 3, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net (Energy Balance)');
    % hold on;
    % plot(t_sim, results.p_g_out_applied_MPC, 'LineWidth', 2, 'Color', 'green', 'DisplayName', 'Grid-Out (Optimizer)');
    % plot(t_sim, results.p_g_in_applied_MPC, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Grid-In (Optimizer)');
    % yline(0, 'k--', 'Alpha', 0.5);
    % xlabel('Time [h]');
    % ylabel('Grid-Power [kW]');
    % title('Grid-Power Comparison: Energy Balance vs. Optimizer Variables');
    % legend('Location', 'best');
    % grid on;
    % xlim([0 max(t_sim)]);

    % subplot(3,1,3);
    % plot(t_sim, results.p_g_out_energy_balance, 'LineWidth', 2, 'Color', [0.5 1 0.5], 'DisplayName', 'Feed-in (from p\_g\_net)');
    % hold on;
    % plot(t_sim, results.p_g_in_energy_balance, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'Consumption (from p\_g\_net)');
    % plot(t_sim, results.p_g_out_applied_MPC, '--', 'LineWidth', 1.5, 'Color', 'green', 'DisplayName', 'Feed-in (Optimizer)');
    % plot(t_sim, results.p_g_in_applied_MPC, '--', 'LineWidth', 1.5, 'Color', 'red', 'DisplayName', 'Consumption (Optimizer)');
    % xlabel('Time [h]');
    % ylabel('Grid-Power [kW]');
    % title('Breakdown: Feed-in vs. Consumption');
    % legend('Location', 'best');
    % grid on;
    % xlim([0 max(t_sim)]);

    %Area plot, der darstellt wo hin der pv überschuss geh oder vonn wo die zu grosse load kompensiert wird
    battery_net_MPC = results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC;
    area_plot_data_MPC = [results.p_g_net_applied_MPC; battery_net_MPC]';

    figure;
    sgtitle('MPC Controller Results');

    subplot(3,1,1);
    plot(t_sim, results.p_net_applied_MPC, 'LineWidth', 2, 'Color', 'green','LineStyle', '--', 'DisplayName', 'Net Power (PV-Load)');
    hold on;
    area_plot = area(t_sim, area_plot_data_MPC, 'LineStyle', 'none');
    colors = {'blue', 'red'};
    names = {'Grid Power', 'Battery Power'};

    for i = 1:numel(area_plot)
        area_plot(i).FaceColor = colors{i};   
        area_plot(i).EdgeColor = 'none';    
        area_plot(i).DisplayName = names{i};
    end
    yline(0, 'k--', 'Alpha', 0.5);
    xlabel('Time [h]');
    ylabel('Power [kW]');
    title('Power Flow Distribution: Battery vs. Grid');
    grid on;
    legend('Location', 'best');
    xlim([0 max(t_sim)]);
    ylim([min(results.p_net_applied_MPC)*1.1, max(results.p_net_applied_MPC)*1.1]);

    subplot(3,1,2);
    plot(t_sim, battery_net_MPC, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Battery Control');
    xlabel('Time [h]');
    ylabel('Power [kW]');
    title('Battery Control Power');
    grid on;
    legend('Location', 'best');
    xlim([0 max(t_sim)]);
    ylim([min(battery_net_MPC)*1.1, max(battery_net_MPC)*1.1]);

    subplot(3,1,3);
    plot((0:options.N_sim)*options.Ts, results.battery_energy_sim_MPC/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'y');
    hold on;
    yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
    xlabel('Time [h]');
    ylabel('[%]');
    title('Battery Energy Evolution (State of Charge)');
    legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
    grid on;
    xlim([0 max(t_sim)]);
    ylim([min(results.battery_energy_sim_MPC)*0.9/model_parameters.E_bat, 1.1]);

    if options.plot_simple_controller

        % Figure 3: System overview (Battery control, PV production and load with Grid-Net)
        figure;
        sgtitle('Simple Controller Results');

        % Subplot 1: Battery control (Charging/Discharging combined)
        subplot(4,1,1);
        plot(t_sim, results.p_b_ch_applied_simple + results.p_b_dch_applied_simple, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Net Battery Control');
        xlabel('Time [h]');
        ylabel('Power [kW]');
        title('Battery Control');
        legend('Location', 'best');
        grid on;
        xlim([0 max(t_sim)]);
        ylim([min(results.p_b_ch_applied_simple + results.p_b_dch_applied_simple)*1.1, max(results.p_b_ch_applied_simple + results.p_b_dch_applied_simple)*1.1]);

        % Subplot 2: PV production
        subplot(4,1,2);
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
        subplot(4,1,3);
        % Extract load data for simulation period
        load_forecast = forecasts.load(1:options.N_sim);
        plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Load');
        hold on;
        plot(t_sim, -results.p_g_net_applied_simple, 'LineWidth', 2, 'Color', 'blue', 'DisplayName', '-Grid-Net-Power');
        yline(0, 'k--', 'Alpha', 0.5);
        xlabel('Time [h]');
        ylabel('Power [kW]');
        title('Load and Grid-Net-Power (pos=Feed-in, neg=Consumption)');
        legend('Location', 'best');
        grid on;
        xlim([0 max(t_sim)]);
        ylim([min([load_forecast, -results.p_g_net_applied_simple])*1.1, max([load_forecast, -results.p_g_net_applied_simple])*1.1]);

        subplot(4,1,4);
        plot((0:options.N_sim)*options.Ts, results.battery_energy_sim_simple/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'y');
        hold on;
        yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
        xlabel('Time [h]');
        ylabel('[%]');
        title('Battery Energy Evolution (State of Charge)');
        legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
        grid on;
        xlim([0 max(t_sim)]);
        ylim([min(results.battery_energy_sim_simple)*0.9/model_parameters.E_bat, 1.1]);

        %Figure 3
        battery_net_simple = results.p_b_ch_applied_simple + results.p_b_dch_applied_simple;
        area_plot_data_simple = [results.p_g_net_applied_simple; battery_net_simple]';

        figure;
        sgtitle('simple Controller Results');

        subplot(3,1,1);
        plot(t_sim, results.p_net_applied_simple, 'LineWidth', 2, 'Color', 'green','LineStyle', '--', 'DisplayName', 'Net Power (PV-Load)');
        hold on;
        area_plot = area(t_sim, area_plot_data_simple, 'LineStyle', 'none');
        colors = {'blue', 'red'};
        names = {'Grid Power', 'Battery Power'};

        for i = 1:numel(area_plot)
            area_plot(i).FaceColor = colors{i};   
            area_plot(i).EdgeColor = 'none';    
            area_plot(i).DisplayName = names{i};
        end
        yline(0, 'k--', 'Alpha', 0.5);
        xlabel('Time [h]');
        ylabel('Power [kW]');
        title('Power Flow Distribution: Battery vs. Grid');
        grid on;
        legend('Location', 'best');
        xlim([0 max(t_sim)]);
        ylim([min(results.p_net_applied_simple)*1.1, max(results.p_net_applied_simple)*1.1]);

        subplot(3,1,2);
        plot(t_sim, battery_net_simple, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Battery Control');
        xlabel('Time [h]');
        ylabel('Power [kW]');
        title('Battery Control Power');
        grid on;
        legend('Location', 'best');
        xlim([0 max(t_sim)]);
        ylim([min(battery_net_simple)*1.1, max(battery_net_simple)*1.1]);

        subplot(3,1,3);
        plot((0:options.N_sim)*options.Ts, results.battery_energy_sim_simple/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'y');
        hold on;
        yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
        xlabel('Time [h]');
        ylabel('[%]');
        title('Battery Energy Evolution (State of Charge)');
        legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
        grid on;
        xlim([0 max(t_sim)]);
        ylim([min(results.battery_energy_sim_simple)*0.9/model_parameters.E_bat, 1.1]);

    end

    Ts = options.Ts; % Sampling time in hours
    N_sim = options.N_sim; % Number of simulation steps
    N_pred = options.N_pred; % Prediction horizon
    battery_energy_sim_MPC = results.battery_energy_sim_MPC;
    p_b_ch_applied_MPC = results.p_b_ch_applied_MPC;
    p_b_dch_applied_MPC = results.p_b_dch_applied_MPC;
    p_g_in_applied_MPC = results.p_g_in_applied_MPC;
    p_g_out_applied_MPC = results.p_g_out_applied_MPC;
    p_g_net_applied_MPC = results.p_g_net_applied_MPC;
    if options.plot_simple_controller
        battery_energy_sim_simple = results.battery_energy_sim_simple;
        p_b_ch_applied_simple = results.p_b_ch_applied_simple;
        p_b_dch_applied_simple = results.p_b_dch_applied_simple;
        p_g_in_applied_simple = results.p_g_in_applied_simple;
        p_g_out_applied_simple = results.p_g_out_applied_simple;
        p_g_net_applied_simple = results.p_g_net_applied_simple;
    end

    if options.plot_simple_controller
        fprintf('\n=== General Sim Info ===\n');
        fprintf('Simulation duration: %.1f hours (%d time steps of %.0f min)\n', N_sim*Ts, N_sim, Ts*60);
        fprintf('Prediction horizon: %.1f hours (%d time steps)\n', N_pred*Ts, N_pred);
        fprintf('Initial battery energy: %.2f kWh\n', battery_energy_sim_MPC(1));

        fprintf('\n=== CONTROLLER COMPARISON TABLE ===\n');
        fprintf('%-35s | %12s | %12s\n', 'Metric', 'MPC', 'Simple');
        fprintf('%-35s-|-%12s-|-%12s\n', repmat('-', 1, 35), repmat('-', 1, 12), repmat('-', 1, 12));
        fprintf('%-35s | %12.2f | %12.2f\n', 'Final battery energy [kWh]', battery_energy_sim_MPC(end), battery_energy_sim_simple(end));
        fprintf('%-35s | %12.2f | %12.2f\n', 'Total battery charging [kWh]', sum(p_b_ch_applied_MPC) * Ts, sum(p_b_ch_applied_simple) * Ts);
        fprintf('%-35s | %12.2f | %12.2f\n', 'Total battery discharging [kWh]', abs(sum(p_b_dch_applied_MPC)) * Ts, abs(sum(p_b_dch_applied_simple)) * Ts);
        fprintf('%-35s | %12.2f | %12.2f\n', 'Total grid consumption [kWh]', abs(sum(p_g_in_applied_MPC)) * Ts, abs(sum(p_g_in_applied_simple)) * Ts);
        fprintf('%-35s | %12.2f | %12.2f\n', 'Total grid feed-in [kWh]', sum(p_g_out_applied_MPC) * Ts, sum(p_g_out_applied_simple) * Ts);
        fprintf('%-35s | %12.2f | %12.2f\n', 'Grid-Net-Energy [kWh]', sum(p_g_net_applied_MPC) * Ts, sum(p_g_net_applied_simple) * Ts);
        fprintf('%-35s | %12.3f | %12.3f\n', 'Average Grid-Net-Power [kW]', mean(p_g_net_applied_MPC), mean(p_g_net_applied_simple));
        fprintf('%-35s | %12.2f | %12.2f\n', 'Max grid feed-in [kW]', max(p_g_net_applied_MPC), max(p_g_net_applied_simple));
        fprintf('%-35s | %12.2f | %12.2f\n', 'Max grid consumption [kW]', min(p_g_net_applied_MPC), min(p_g_net_applied_simple));
        fprintf('====================================\n\n');

    else
        fprintf('\n=== MPC RECEDING HORIZON SIMULATION SUMMARY ===\n');
        fprintf('Simulation duration: %.1f hours (%d time steps of %.0f min)\n', N_sim*Ts, N_sim, Ts*60);
        fprintf('Prediction horizon: %.1f hours (%d time steps)\n', N_pred*Ts, N_pred);
        fprintf('Initial battery energy: %.2f kWh\n', battery_energy_sim_MPC(1));
        fprintf('Final battery energy: %.2f kWh\n', battery_energy_sim_MPC(end));
        fprintf('Total battery charging: %.2f kWh\n', sum(p_b_ch_applied_MPC) * Ts);
        fprintf('Total battery discharging: %.2f kWh\n', abs(sum(p_b_dch_applied_MPC)) * Ts);
        fprintf('Total grid consumption: %.2f kWh\n', abs(sum(p_g_in_applied_MPC)) * Ts);
        fprintf('Total grid feed-in: %.2f kWh\n', sum(p_g_out_applied_MPC) * Ts);
        fprintf('Grid-Net-Energy: %.2f kWh (pos=Feed-in, neg=Consumption)\n', sum(p_g_net_applied_MPC) * Ts);
        fprintf('Average Grid-Net-Power: %.3f kW\n', mean(p_g_net_applied_MPC));
        fprintf('Max grid feed-in: %.2f kW\n', max(p_g_net_applied_MPC));
        fprintf('Max grid consumption: %.2f kW\n', min(p_g_net_applied_MPC));
        fprintf('======================================================\n\n');
    end


end