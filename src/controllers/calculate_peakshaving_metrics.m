function [metrics_MPC, metrics_baseline] = calculate_peakshaving_metrics(p_grid_net_MPC, p_grid_net_baseline, peakshaving_metrics_options)

    P_max_MPC_feed_in_grid = -max(-p_grid_net_MPC);
    P_max_baseline_feed_in_grid = -max(-p_grid_net_baseline);
    P_max_grid_consumption_MPC = max(p_grid_net_MPC);
    P_max_grid_consumption_baseline = max(p_grid_net_baseline);

    p_ref = peakshaving_metrics_options.p_ref;

    n_P_gridfeed_in_higher_than_pref_MPC = sum(-p_grid_net_MPC > p_ref);
    n_P_gridfeed_in_higher_than_pref_baseline = sum(-p_grid_net_baseline > p_ref);
    n_P_gridcons_higher_than_pref_MPC = sum(p_grid_net_MPC > p_ref);
    n_P_gridcons_higher_than_pref_baseline = sum(p_grid_net_baseline > p_ref);

    sum_P_gridfeed_in_higher_than_pref_MPC = sum((-p_grid_net_MPC - p_ref).*(-p_grid_net_MPC > p_ref));
    sum_P_gridfeed_in_higher_than_pref_baseline = sum((-p_grid_net_baseline - p_ref).*(-p_grid_net_baseline > p_ref));
    sum_P_gridcons_higher_than_pref_MPC = sum((p_grid_net_MPC - p_ref).*(p_grid_net_MPC > p_ref));
    sum_P_gridcons_higher_than_pref_baseline = sum((p_grid_net_baseline - p_ref).*(p_grid_net_baseline > p_ref));

    if peakshaving_metrics_options.plot_peakshaving_metrics
        figure;
        hold on;
        plot(p_grid_net_MPC, 'LineWidth', 1.5);
        plot(p_grid_net_baseline, 'LineWidth', 1.5);
        yline(p_ref, 'r--', 'p_{ref}', 'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'middle', 'FontSize', 12);
        yline(-p_ref, 'r--', '-p_{ref}', 'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'middle', 'FontSize', 12);
        xlabel('Time step');
        ylabel('Grid power (kW)');
        title('Grid Power with MPC vs Baseline');
        legend('MPC Grid Power', 'Baseline Grid Power', 'Location', 'Best');
        xlim([1, length(p_grid_net_MPC)]);
        grid on;
        hold off;
    end
    
    % Print peakshaving metrics in table format
    fprintf('\n=== PEAKSHAVING METRICS COMPARISON ===\n');
    fprintf('%-45s | %12s | %12s\n', 'Metric', 'MPC', 'Baseline');
    fprintf('%-45s-|-%12s-|-%12s\n', repmat('-', 1, 45), repmat('-', 1, 12), repmat('-', 1, 12));
    fprintf('%-45s | %12.2f | %12.2f\n', 'Max Grid Feed-in [kW]', P_max_MPC_feed_in_grid, P_max_baseline_feed_in_grid);
    fprintf('%-45s | %12.2f | %12.2f\n', 'Max Grid Consumption [kW]', P_max_grid_consumption_MPC, P_max_grid_consumption_baseline);
    fprintf('%-45s | %12d | %12d\n', 'Count: Feed-in > p_ref', n_P_gridfeed_in_higher_than_pref_MPC, n_P_gridfeed_in_higher_than_pref_baseline);
    fprintf('%-45s | %12d | %12d\n', 'Count: Consumption > p_ref', n_P_gridcons_higher_than_pref_MPC, n_P_gridcons_higher_than_pref_baseline);
    fprintf('%-45s | %12.2f | %12.2f\n', 'Sum excess Feed-in [kW]', sum_P_gridfeed_in_higher_than_pref_MPC, sum_P_gridfeed_in_higher_than_pref_baseline);
    fprintf('%-45s | %12.2f | %12.2f\n', 'Sum excess Consumption [kW]', sum_P_gridcons_higher_than_pref_MPC, sum_P_gridcons_higher_than_pref_baseline);
    fprintf('%-45s | %12.2f | %12.2f\n', 'Reference power p_ref [kW]', p_ref, p_ref);
    fprintf('======================================\n\n');
    
    % Return structured metrics
    metrics_MPC = struct(...
        'max_feed_in', P_max_MPC_feed_in_grid, ...
        'max_consumption', P_max_grid_consumption_MPC, ...
        'count_feed_in_above_pref', n_P_gridfeed_in_higher_than_pref_MPC, ...
        'count_consumption_above_pref', n_P_gridcons_higher_than_pref_MPC, ...
        'sum_excess_feed_in', sum_P_gridfeed_in_higher_than_pref_MPC, ...
        'sum_excess_consumption', sum_P_gridcons_higher_than_pref_MPC);
        
    metrics_baseline = struct(...
        'max_feed_in', P_max_baseline_feed_in_grid, ...
        'max_consumption', P_max_grid_consumption_baseline, ...
        'count_feed_in_above_pref', n_P_gridfeed_in_higher_than_pref_baseline, ...
        'count_consumption_above_pref', n_P_gridcons_higher_than_pref_baseline, ...
        'sum_excess_feed_in', sum_P_gridfeed_in_higher_than_pref_baseline, ...
        'sum_excess_consumption', sum_P_gridcons_higher_than_pref_baseline);

end