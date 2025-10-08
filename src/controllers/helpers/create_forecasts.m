function [pv_forecast, load_forecast, t] = create_forecasts(N_pred, take_dummy_forecasts)


    n_days_forecast = 3; 
    plot_real_forecast = false;

    if take_dummy_forecasts

        % Create extended dummy forecasts (multiple days by copying)
        [dummy_pv_base, t_base] = linear_peak_series(5, 10, 7, 13, N_pred);
        [dummy_load_base, ~] = linear_peak_series(3, 21, 18, 23, N_pred);

        
        dummy_pv_extended = repmat(dummy_pv_base, 1, n_days_forecast);
        dummy_load_extended = repmat(dummy_load_base, 1, n_days_forecast);
        t_extended = linspace(0, 24*n_days_forecast, length(dummy_pv_extended));

        pv_forecast = dummy_pv_extended;
        load_forecast = dummy_load_extended;
        t = t_extended;

    else
        % load real forecast from .mat file
        T_real = load('data/RAPT Dataset/matlab_datasets/dfA_300s_3months_7days_15min.mat');
        pv_forecast = T_real.T_filtered.A_exp_power(1:N_pred*n_days_forecast)'/1000; % convert W to kW
        load_forecast = T_real.T_filtered.A_total_cons_power_min_sauna(1:N_pred*n_days_forecast)'/1000; % convert W to kW
        t = linspace(0, 24*n_days_forecast, length(pv_forecast));

        if plot_real_forecast
            figure;
            plot(t, pv_forecast, 'b', 'DisplayName', 'PV Forecast');
            hold on;
            plot(t, load_forecast, 'r', 'DisplayName', 'Load Forecast');
            xlabel('Time (hours)');
            ylabel('Power (kW)');
            title('Real PV and Load Forecasts');
            legend;
            grid on;
            xlim([0, 24*n_days_forecast]);
        end


    end
    

end

function [y, t] = linear_peak_series(peak_value, peak_hour, start_hour, end_hour, N)
% linear_peak_series erzeugt eine diskrete Zahlenreihe mit Peak
%
% Inputs:
%   peak_value  - Höhe des Peaks
%   peak_hour   - Zeitpunkt des Peaks in Stunden (muss zwischen start und end sein)
%   start_hour  - Startzeit in Stunden, davor y = 0
%   end_hour    - Endzeit in Stunden, danach y = 0
%   N           - Anzahl der Datenpunkte
%
% Outputs:
%   y - Werte der Zahlenreihe (Länge N)
%   t - Zeitpunkte in Stunden (Länge N)

% Zeitvektor über 24 Stunden
t = linspace(0, 24, N);

% Indizes für Start, Peak und Ende
start_idx = max(round(start_hour/24 * N), 1);
peak_idx  = max(round(peak_hour/24  * N), start_idx);
end_idx   = min(round(end_hour/24   * N), N);

% Vektor initialisieren
y = zeros(1, N);

% Linearer Anstieg von start bis peak
y(start_idx:peak_idx) = linspace(0, peak_value, peak_idx - start_idx + 1);

% Linearer Abfall von peak bis end
y(peak_idx:end_idx) = linspace(peak_value, 0, end_idx - peak_idx + 1);

% Vor start und nach end bleibt y = 0

end