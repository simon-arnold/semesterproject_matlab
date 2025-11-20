function plot_controller_results(correct_load_pv_data, results, model_parameters, options )
    %TODO: Add description
    %% Plotting the results

    % Use actual length of results arrays (in case N_sim was updated)
    actual_N_sim = length(results.p_b_ch_applied_MPC);

    disp("correct_load_pv_data.t length:" + length(correct_load_pv_data.t));
    disp("actual_N_sim:" + actual_N_sim);
    
    % Time vector for simulation (using actual datetime data)
    t_sim = correct_load_pv_data.t(1:actual_N_sim);
    t_full = (0:options.N_pred-1) * options.Ts;

    % Create title suffix based on configuration
    title_suffix = '';
    if isfield(results, 'use_nn_predictor') && results.use_nn_predictor
        title_suffix = ' (mit NN-Prädiktor)';
    end
    if isfield(results, 'use_real_data') && results.use_real_data
        if ~isempty(title_suffix)
            title_suffix = [title_suffix, ' und echten Daten'];
        else
            title_suffix = ' (mit echten Daten)';
        end
    end
    
    %% Figure 1: Forecasts over prediction horizon
    figure;
    sgtitle(["PV and Load over testing period"]);
    ax1 = subplot(2,1,1);
    plot(correct_load_pv_data.t, correct_load_pv_data.pv, 'LineWidth', 2, 'Color', [1 0.5 0]);
    xlabel('Time');
    ylabel('PV Power [kW]');
    title(['PV Data']);
    grid on;
    xlim([correct_load_pv_data.t(1) correct_load_pv_data.t(end)]);

    ax2 = subplot(2,1,2);
    plot(correct_load_pv_data.t, correct_load_pv_data.load, 'LineWidth', 2, 'Color', 'blue');
    xlabel('Time');
    ylabel('Load [kW]');
    title(['Load Data']);
    grid on;
    xlim([correct_load_pv_data.t(1) correct_load_pv_data.t(end)]);
    
    % Synchronize x-axes
    linkaxes([ax1, ax2], 'x');

    %% Figure 2: HEMS Overview - All Power Flows
    figure;
    sgtitle(['HEMS Power Flow Overview', title_suffix]);
    
    % Extract data for simulation period
    pv_forecast = correct_load_pv_data.pv(1:actual_N_sim);
    load_forecast = correct_load_pv_data.load(1:actual_N_sim);
    battery_net_MPC = results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC;
    
    % Subplot 1: PV Production and Load
    ax1 = subplot(3,1,1);
    plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.6 0], 'DisplayName', 'PV Production');
    hold on;
    plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', [0.2 0.4 0.8], 'DisplayName', 'Load');
    plot(t_sim, pv_forecast - load_forecast, 'LineWidth', 2, 'Color', [0.4 0.9 0.4], 'DisplayName', 'Net Power (PV-Load)');
    xlabel('Time');
    ylabel('Power [kW]');
    title('PV Production vs. Load');
    legend('Location', 'best');
    grid on;
    xlim([t_sim(1) t_sim(end)]);
    
    % Subplot 2: Power Distribution (Battery and Grid)
    ax2 = subplot(3,1,2);
    % yyaxis left
    plot(t_sim, battery_net_MPC, 'LineWidth', 2.5, 'Color', [0.8 0.2 0.2], 'DisplayName', 'Battery Power');
    hold on;
    plot(t_sim, results.p_g_net_applied_MPC, 'LineWidth', 2.5, 'Color', [0.2 0.6 0.8], 'DisplayName', 'Grid Power');
    ylabel('Power [kW]');
    ylim([min([results.p_g_net_applied_MPC, battery_net_MPC])*1.2, max([results.p_g_net_applied_MPC, battery_net_MPC])*1.2]);
    xlabel('Time');
    title('Battery and Grid Power (pos=Charge/Sell, neg=Discharge/Consumption)');
    legend('Location', 'best');
    grid on;
    xlim([t_sim(1) t_sim(end)]);
    
    % Subplot 3: Battery State of Charge
    ax3 = subplot(3,1,3);
    plot(t_sim, results.battery_energy_sim_MPC(1:actual_N_sim)/model_parameters.E_bat * 100, 'LineWidth', 2.5, 'Color', 'black');
    hold on;
    yline((1-model_parameters.DOD)*100, '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
    yline(100, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
    xlabel('Time');
    ylabel('SOC [%]');
    title('Battery State of Charge');
    legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
    grid on;
    xlim([t_sim(1) t_sim(end)]);
    ylim([min(results.battery_energy_sim_MPC(1:actual_N_sim))*0.9/model_parameters.E_bat * 100, 105]);
    
    % Synchronize x-axes
    linkaxes([ax1, ax2, ax3], 'x');

    % %% Figure 3: System overview (Battery control, PV production and load with Grid-Net)
    % figure;
    % sgtitle(['MPC Controller Results', title_suffix]);

    % % Subplot 1: Battery control (Charging/Discharging combined)
    % ax1 = subplot(4,1,1);
    % plot(t_sim, results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Net Battery Control');
    % xlabel('Time');
    % ylabel('Power [kW]');
    % title('Battery Control');
    % legend('Location', 'best');
    % grid on;
    % xlim([t_sim(1) t_sim(end)]);
    % ylim([min(results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC)*1.1, max(results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC)*1.1]);

    % % Subplot 2: PV production
    % ax2 = subplot(4,1,2);
    % % Extract PV data for simulation period
    % pv_forecast = correct_load_pv_data.pv(1:actual_N_sim);
    % plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'PV Production');
    % xlabel('Time');
    % ylabel('PV Power [kW]');
    % title('PV Production');
    % legend('Location', 'best');
    % grid on;
    % xlim([t_sim(1) t_sim(end)]);

    % % Subplot 3: Load and Grid-Net-Power
    % ax3 = subplot(4,1,3);
    % % Extract load data for simulation period
    % load_forecast = correct_load_pv_data.load(1:actual_N_sim);
    % plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Load');
    % hold on;
    % plot(t_sim, -results.p_g_net_applied_MPC, 'LineWidth', 2, 'Color', 'blue', 'DisplayName', '-Grid-Net-Power');
    % yline(0, 'k--', 'Alpha', 0.5);
    % xlabel('Time');
    % ylabel('Power [kW]');
    % title('Load and Grid-Net-Power (pos=Feed-in, neg=Consumption)');
    % legend('Location', 'best');
    % grid on;
    % xlim([t_sim(1) t_sim(end)]);
    % ylim([min([load_forecast, -results.p_g_net_applied_MPC])*1.1, max([load_forecast, -results.p_g_net_applied_MPC])*1.1]);

    % ax4 = subplot(4,1,4);
    % plot(t_sim, results.battery_energy_sim_MPC(1:actual_N_sim)/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'black');
    % hold on;
    % yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
    % yline(1.0, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
    % xlabel('Time');
    % ylabel('[%]');
    % title('Battery Energy Evolution (State of Charge)');
    % legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
    % grid on;
    % xlim([t_sim(1) t_sim(end)]);
    % ylim([min(results.battery_energy_sim_MPC(1:actual_N_sim))*0.9/model_parameters.E_bat, 1.1]);
    
    % % Synchronize x-axes
    % linkaxes([ax1, ax2, ax3, ax4], 'x');

    % Figure 4: Receding Horizon Simulation Results
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
        % plot(t_sim, results.p_g_out_energy_balance, 'LineWidth', 2, 'Color', [51 204 51]/255, 'DisplayName', 'Feed-in (from p_g_net)');
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

    %% Figure 3 Area plot, der darstellt wo hin der pv überschuss geh oder vonn wo die zu grosse load kompensiert wird
    battery_net_MPC = results.p_b_ch_applied_MPC + results.p_b_dch_applied_MPC;
    area_plot_data_MPC = [results.p_g_net_applied_MPC; battery_net_MPC]';

    figure;
    sgtitle(['MPC Controller Results', title_suffix]);

    % Subplot 1: PV Production and Load
    ax1 = subplot(3,1,1);
    plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.6 0], 'DisplayName', 'PV Production');
    hold on;
    plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', [0.2 0.4 0.8], 'DisplayName', 'Load');
    plot(t_sim, pv_forecast - load_forecast, 'LineWidth', 2, 'Color', [0.4 0.9 0.4], 'DisplayName', 'Net Power (PV-Load)');
    xlabel('Time');
    ylabel('Power [kW]');
    title('PV Production vs. Load');
    legend('Location', 'best');
    grid on;
    xlim([t_sim(1) t_sim(end)]);


    ax3 = subplot(3,1,2);
    hold on;
    area_plot = area(t_sim, area_plot_data_MPC, 'LineStyle', 'none');
    colors = {'blue', 'red'};
    names = {'Grid Power', 'Battery Power'};

    for i = 1:numel(area_plot)
        area_plot(i).FaceColor = colors{i};   
        area_plot(i).EdgeColor = 'none';    
        area_plot(i).DisplayName = names{i};
    end

    xlabel('Time');
    ylabel('Power [kW]');
    plot(t_sim, results.p_net_applied_MPC, 'LineWidth', 2, 'Color', [0.4 0.9 0.4], 'DisplayName', 'Net Power (PV-Load)');
    title('Power Flow Distribution: Battery vs. Grid');
    grid on;
    legend('Location', 'best');
    xlim([t_sim(1) t_sim(end)]);
    ylim([min(results.p_net_applied_MPC)*1.1, max(results.p_net_applied_MPC)*1.1]);

    % ax2 = subplot(3,1,2);
    % plot(t_sim, battery_net_MPC, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Battery Control');
    % xlabel('Time');
    % ylabel('Power [kW]');
    % title('Battery Control Power');
    % grid on;
    % legend('Location', 'best');
    % xlim([t_sim(1) t_sim(end)]);
    % ylim([min(battery_net_MPC)*1.1, max(battery_net_MPC)*1.1]);

    ax3 = subplot(3,1,3);
    plot(t_sim, results.battery_energy_sim_MPC(1:actual_N_sim)/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'black');
    hold on;
    yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
    yline(1.0, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
    xlabel('Time');
    ylabel('[%]');
    title('Battery Energy Evolution (State of Charge)');
    legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
    grid on;
    xlim([t_sim(1) t_sim(end)]);
    ylim([min(results.battery_energy_sim_MPC(1:actual_N_sim))*0.9/model_parameters.E_bat, 1.1]);
    
    % Synchronize x-axes
    linkaxes([ax1, ax2, ax3], 'x');

    % figure;
    % sgtitle(['MPC Controller Results', title_suffix]);

    % ax1 = subplot(3,1,1);
    % hold on;
    % area_plot = area(t_sim, area_plot_data_MPC, 'LineStyle', 'none');
    % colors = {'blue', 'red'};
    % names = {'Grid Power', 'Battery Power'};

    % for i = 1:numel(area_plot)
    %     area_plot(i).FaceColor = colors{i};   
    %     area_plot(i).EdgeColor = 'none';    
    %     area_plot(i).DisplayName = names{i};
    % end

    % xlabel('Time');
    % ylabel('Power [kW]');
    % plot(t_sim, results.p_net_applied_MPC, 'LineWidth', 2, 'Color', [0 153 51]/255, 'DisplayName', 'Net Power (PV-Load)');
    % title('Power Flow Distribution: Battery vs. Grid');
    % grid on;
    % legend('Location', 'best');
    % xlim([t_sim(1) t_sim(end)]);
    % ylim([min(results.p_net_applied_MPC)*1.1, max(results.p_net_applied_MPC)*1.1]);

    % ax2 = subplot(3,1,2);
    % pv_forecast = correct_load_pv_data.pv(1:actual_N_sim);
    % plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'PV Production');
    % xlabel('Time');
    % ylabel('PV Power [kW]');
    % title('PV Production');
    % legend('Location', 'best');
    % grid on;
    % xlim([t_sim(1) t_sim(end)]);

    % ax3 = subplot(3,1,3);
    % plot(t_sim, results.battery_energy_sim_MPC(1:actual_N_sim)/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'black');
    % hold on;
    % yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
    % yline(1.0, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
    % xlabel('Time');
    % ylabel('[%]');
    % title('Battery Energy Evolution (State of Charge)');
    % legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
    % grid on;
    % xlim([t_sim(1) t_sim(end)]);
    % ylim([min(results.battery_energy_sim_MPC(1:actual_N_sim))*0.9/model_parameters.E_bat, 1.1]);
    
    % % Synchronize x-axes
    % linkaxes([ax1, ax2, ax3], 'x');



    if options.plot_simple_controller

        % % Figure 3: System overview (Battery control, PV production and load with Grid-Net)
        % figure;
        % sgtitle(['Simple Controller Results', title_suffix]);

        % % Subplot 1: Battery control (Charging/Discharging combined)
        % ax1 = subplot(4,1,1);
        % plot(t_sim, results.p_b_ch_applied_simple + results.p_b_dch_applied_simple, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Net Battery Control');
        % xlabel('Time');
        % ylabel('Power [kW]');
        % title('Battery Control');
        % legend('Location', 'best');
        % grid on;
        % xlim([t_sim(1) t_sim(end)]);
        % ylim([min(results.p_b_ch_applied_simple + results.p_b_dch_applied_simple)*1.1, max(results.p_b_ch_applied_simple + results.p_b_dch_applied_simple)*1.1]);

        % % Subplot 2: PV production
        % ax2 = subplot(4,1,2);
        % % Extract PV data for simulation period
        % pv_forecast = correct_load_pv_data.pv(1:actual_N_sim);
        % plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'PV Production');
        % xlabel('Time');
        % ylabel('PV Power [kW]');
        % title('PV Production');
        % legend('Location', 'best');
        % grid on;
        % xlim([t_sim(1) t_sim(end)]);

        % % Subplot 3: Load and Grid-Net-Power
        % ax3 = subplot(4,1,3);
        % % Extract load data for simulation period
        % load_forecast = correct_load_pv_data.load(1:actual_N_sim);
        % plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Load');
        % hold on;
        % plot(t_sim, -results.p_g_net_applied_simple, 'LineWidth', 2, 'Color', 'blue', 'DisplayName', '-Grid-Net-Power');
        % yline(0, 'k--', 'Alpha', 0.5);
        % xlabel('Time');
        % ylabel('Power [kW]');
        % title('Load and Grid-Net-Power (pos=Feed-in, neg=Consumption)');
        % legend('Location', 'best');
        % grid on;
        % xlim([t_sim(1) t_sim(end)]);
        % ylim([min([load_forecast, -results.p_g_net_applied_simple])*1.1, max([load_forecast, -results.p_g_net_applied_simple])*1.1]);

        % ax4 = subplot(4,1,4);
        % plot(t_sim, results.battery_energy_sim_simple(1:actual_N_sim)/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'black');
        % hold on;
        % yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
        % yline(1.0, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
        % xlabel('Time');
        % ylabel('[%]');
        % title('Battery Energy Evolution (State of Charge)');
        % legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
        % grid on;
        % xlim([t_sim(1) t_sim(end)]);
        % ylim([min(results.battery_energy_sim_simple(1:actual_N_sim))*0.9/model_parameters.E_bat, 1.1]);
        
        % % Synchronize x-axes
        % linkaxes([ax1, ax2, ax3, ax4], 'x');

        %% Figure 4
        battery_net_simple = results.p_b_ch_applied_simple + results.p_b_dch_applied_simple;

        figure;
        sgtitle(['Simple Controller Results', title_suffix]);

        % Subplot 1: PV Production and Load
        ax1 = subplot(3,1,1);
        plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.6 0], 'DisplayName', 'PV Production');
        hold on;
        plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', [0.2 0.4 0.8], 'DisplayName', 'Load');
        plot(t_sim, pv_forecast - load_forecast, 'LineWidth', 2, 'Color', [0.4 0.9 0.4], 'DisplayName', 'Net Power (PV-Load)');
        xlabel('Time');
        ylabel('Power [kW]');
        title('PV Production vs. Load');
        legend('Location', 'best');
        grid on;
        xlim([t_sim(1) t_sim(end)]);

        ax2 = subplot(3,1,2);
        % yyaxis left
        plot(t_sim, battery_net_simple, 'LineWidth', 2.5, 'Color', [0.8 0.2 0.2], 'DisplayName', 'Battery Power');
        hold on;
        plot(t_sim, results.p_g_net_applied_simple, 'LineWidth', 2.5, 'Color', [0.2 0.6 0.8], 'DisplayName', 'Grid Power');
        ylabel('Power [kW]');
        ylim([min([results.p_g_net_applied_simple, battery_net_simple])*1.2, max([results.p_g_net_applied_simple, battery_net_simple])*1.2]);
        xlabel('Time');
        title('Battery and Grid Power (pos=Charge/Sell, neg=Discharge/Consumption)');
        legend('Location', 'best');
        grid on;
        xlim([t_sim(1) t_sim(end)]);

        ax3 = subplot(3,1,3);
        plot(t_sim, results.battery_energy_sim_simple(1:actual_N_sim)/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'black');
        hold on;
        yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
        yline(1.0, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
        xlabel('Time');
        ylabel('[%]');
        title('Battery Energy Evolution (State of Charge)');
        legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
        grid on;
        xlim([t_sim(1) t_sim(end)]);
        ylim([min(results.battery_energy_sim_simple(1:actual_N_sim))*0.9/model_parameters.E_bat, 1.1]);
        
        % Synchronize x-axes
        linkaxes([ax1, ax2, ax3], 'x');


        %% Figure 5
        
        area_plot_data_simple = [results.p_g_net_applied_simple; battery_net_simple]';

        figure;
        sgtitle(['Simple Controller Results', title_suffix]);

        % Subplot 1: PV Production and Load
        ax1 = subplot(3,1,1);
        plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.6 0], 'DisplayName', 'PV Production');
        hold on;
        plot(t_sim, load_forecast, 'LineWidth', 2, 'Color', [0.2 0.4 0.8], 'DisplayName', 'Load');
        plot(t_sim, pv_forecast - load_forecast, 'LineWidth', 2, 'Color', [0.4 0.9 0.4], 'DisplayName', 'Net Power (PV-Load)');
        xlabel('Time');
        ylabel('Power [kW]');
        title('PV Production vs. Load');
        legend('Location', 'best');
        grid on;
        xlim([t_sim(1) t_sim(end)]);

        ax2 = subplot(3,1,2);
        hold on;
        area_plot = area(t_sim, area_plot_data_simple, 'LineStyle', 'none');
        colors = {'blue', 'red'};
        names = {'Grid Power', 'Battery Power'};

        for i = 1:numel(area_plot)
            area_plot(i).FaceColor = colors{i};   
            area_plot(i).EdgeColor = 'none';    
            area_plot(i).DisplayName = names{i};
        end
        xlabel('Time');
        ylabel('Power [kW]');
        title('Power Flow Distribution: Battery vs. Grid');
        plot(t_sim, results.p_net_applied_simple, 'LineWidth', 2, 'Color', [0.4 0.9 0.4], 'DisplayName', 'Net Power (PV-Load)');
        grid on;
        legend('Location', 'best');
        xlim([t_sim(1) t_sim(end)]);
        ylim([min(results.p_net_applied_simple)*1.1, max(results.p_net_applied_simple)*1.1]);

        % ax2 = subplot(3,1,2);
        % plot(t_sim, battery_net_simple, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Battery Control');
        % xlabel('Time');
        % ylabel('Power [kW]');
        % title('Battery Control Power');
        % grid on;
        % legend('Location', 'best');
        % xlim([t_sim(1) t_sim(end)]);
        % ylim([min(battery_net_simple)*1.1, max(battery_net_simple)*1.1]);

        ax3 = subplot(3,1,3);
        plot(t_sim, results.battery_energy_sim_simple(1:actual_N_sim)/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'black');
        hold on;
        yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
        yline(1.0, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
        xlabel('Time');
        ylabel('[%]');
        title('Battery Energy Evolution (State of Charge)');
        legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
        grid on;
        xlim([t_sim(1) t_sim(end)]);
        ylim([min(results.battery_energy_sim_simple(1:actual_N_sim))*0.9/model_parameters.E_bat, 1.1]);
        
        % Synchronize x-axes
        linkaxes([ax1, ax2, ax3], 'x');

        % figure;
        % sgtitle(['Simple Controller Results', title_suffix]);

        % ax1 = subplot(3,1,1);
        % hold on;
        % area_plot = area(t_sim, area_plot_data_simple, 'LineStyle', 'none');
        % colors = {'blue', 'red'};
        % names = {'Grid Power', 'Battery Power'};

        % for i = 1:numel(area_plot)
        %     area_plot(i).FaceColor = colors{i};   
        %     area_plot(i).EdgeColor = 'none';    
        %     area_plot(i).DisplayName = names{i};
        % end
        % yline(0, 'k--', 'Alpha', 0.5);
        % xlabel('Time');
        % ylabel('Power [kW]');
        % title('Power Flow Distribution: Battery vs. Grid');
        % plot(t_sim, results.p_net_applied_simple, 'LineWidth', 2, 'Color', [0 153 51]/255, 'DisplayName', 'Net Power (PV-Load)');
        % grid on;
        % legend('Location', 'best');
        % xlim([t_sim(1) t_sim(end)]);
        % ylim([min(results.p_net_applied_simple)*1.1, max(results.p_net_applied_simple)*1.1]);

        % ax2 = subplot(3,1,2);
        % pv_forecast = correct_load_pv_data.pv(1:actual_N_sim);
        % plot(t_sim, pv_forecast, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'PV Production');
        % xlabel('Time');
        % ylabel('PV Power [kW]');
        % title('PV Production');
        % legend('Location', 'best');
        % grid on;
        % xlim([t_sim(1) t_sim(end)]);

        % ax3 = subplot(3,1,3);
        % plot(t_sim, results.battery_energy_sim_simple(1:actual_N_sim)/model_parameters.E_bat, 'LineWidth', 2, 'Color', 'black');
        % hold on;
        % yline((1-model_parameters.DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
        % yline(1.0, '--', 'Color', [0 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'Max SOC');
        % xlabel('Time');
        % ylabel('[%]');
        % title('Battery Energy Evolution (State of Charge)');
        % legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
        % grid on;
        % xlim([t_sim(1) t_sim(end)]);
        % ylim([min(results.battery_energy_sim_simple(1:actual_N_sim))*0.9/model_parameters.E_bat, 1.1]);
        
        % % Synchronize x-axes
        % linkaxes([ax1, ax2, ax3], 'x');

    end

    Ts = options.Ts; % Sampling time in hours
    N_sim = actual_N_sim; % Number of simulation steps (use actual length)
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