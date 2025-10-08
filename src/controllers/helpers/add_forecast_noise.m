function [pv_forecast_noise,load_forecast_noise] = add_forecast_noise(pv_forecast, load_forecast, k_sim, N_pred, Ts, noise_options)
    plot_forecasts_with_noise = true;

    % Der erste Eintrag bleibt gleich - der ist korrekt
    pv_forecast_noise(1) = pv_forecast(1);
    load_forecast_noise(1) = load_forecast(1);

    pv_forecast_noise = [ pv_forecast_noise, max(0, pv_forecast(2:end) + normrnd(0, noise_options.pv_std, size(pv_forecast(2:end))))];
    load_forecast_noise = [ load_forecast_noise, max(0, load_forecast(2:end) + normrnd(0, noise_options.load_std, size(load_forecast(2:end))))];

    if plot_forecasts_with_noise && k_sim == 1
        figure;
        t = linspace(0, N_pred*Ts, length(pv_forecast));


        subplot(2,1,1);
        plot(t, pv_forecast, 'o--', 'DisplayName', 'PV Forecast (clean)');
        hold on;
        plot(t, pv_forecast_noise, '-', 'Color', [1 0.5 0], 'LineWidth', 1.5, 'DisplayName', 'PV Forecast (with noise)');
        xlabel('Time (hours)');
        ylabel('Power (kW)');
        title('PV Forecast with Added Noise for time step 1');
        legend;
        grid on;
        xlim([0, N_pred*Ts]);
        ylim([0, max(pv_forecast)*1.2]);

        subplot(2,1,2);
        plot(t, load_forecast, 'o--', 'DisplayName', 'Load Forecast (clean)');
        hold on;
        plot(t, load_forecast_noise, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Load Forecast (with noise)');
        xlabel('Time (hours)');
        ylabel('Power (kW)');
        title('Load Forecast with Added Noise for time step 1');
        legend;
        grid on;
        xlim([0, N_pred*Ts]);
        ylim([0, max(load_forecast)*1.2]);
        
        
        drawnow;
        pause(0.1);  
    end
end