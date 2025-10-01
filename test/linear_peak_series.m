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


