close all

%% Parameter Setup
Ts = 15/60; % in Stunden (15 Minuten)
N_pred = 24/Ts; % Vorhersagerhorizont: 24 Stunden in Zeitschritten
N_sim = 48/Ts; % Simulationszeit: 48 Stunden in Zeitschritten (2 Tage)

% Erstelle erweiterte Dummy-Vorhersagen (mehrere Tage durch Kopieren)
[dummy_pv_base, t_base] = linear_peak_series(5, 10, 7, 13, N_pred);
[dummy_load_base, ~] = linear_peak_series(3, 21, 18, 23, N_pred);

% Erweitere die Vorhersagen durch Kopieren für mehrere Tage
n_days_forecast = 3; % 3 Tage Vorhersage verfügbar
dummy_pv_extended = repmat(dummy_pv_base, 1, n_days_forecast);
dummy_load_extended = repmat(dummy_load_base, 1, n_days_forecast);
t_extended = linspace(0, 24*n_days_forecast, length(dummy_pv_extended));

% Plot der ursprünglichen Vorhersagen
figure;
plot(t_base, dummy_pv_base, 'LineWidth', 2)
hold on
plot(t_base, dummy_load_base, 'LineWidth', 2)
xlabel('Stunde')
ylabel('Wert [kW]')
title('Basis-Vorhersagen (ein Tag)')
legend('PV-Vorhersage', 'Last-Vorhersage', 'Location', 'best')
grid on
xlim([0 24])

%% MPC Parameter
R_cost = diag([100, 100, 2000]); 
nu_ch = 0.85;
nu_dch = 0.95;
L_bat = 0;
E_bat = 3;
DOD = 0.4;
P_batconv_max = 1.8;
P_gridcons_max = 30;

%% MPC Controller Initialisierung
mpc = MPC_Controller(24, N_pred, Ts, R_cost, nu_ch, nu_dch, L_bat, E_bat, DOD, P_batconv_max, P_gridcons_max);

%% Receding Horizon Simulation
x_current = 2.5; % Anfängliche Batteriekapazität in kWh (muss > 1.8 kWh sein)

% Initialisierung der Speicher-Arrays für Simulation
battery_energy_sim = zeros(1, N_sim+1);
p_b_ch_applied = zeros(1, N_sim);
p_b_dch_applied = zeros(1, N_sim);
p_g_in_applied = zeros(1, N_sim);
p_g_out_applied = zeros(1, N_sim);
p_net_applied = zeros(1, N_sim);
p_g_net_applied = zeros(1, N_sim);  % Aus Energiebilanz berechnete Net-Grid-Power

battery_energy_sim(1) = x_current;

fprintf('Starte Receding Horizon Simulation über %d Zeitschritte (%.1f Stunden)...\n', N_sim, N_sim*Ts);

for k = 1:N_sim
    % Aktueller Zeitschritt
    fprintf('Zeitschritt %d/%d (%.2f h): ', k, N_sim, (k-1)*Ts);
    
    % Extrahiere Vorhersage-Fenster für aktuellen Zeitschritt
    start_idx = k;
    end_idx = k + N_pred - 1;
    
    % Überprüfe, ob genug Vorhersagedaten vorhanden sind
    if end_idx > length(dummy_pv_extended)
        fprintf('Warnung: Nicht genug Vorhersagedaten! Verwende verfügbare Daten.\n');
        end_idx = length(dummy_pv_extended);
        current_N_pred = end_idx - start_idx + 1;
        
        pv_forecast_window = dummy_pv_extended(start_idx:end_idx);
        load_forecast_window = dummy_load_extended(start_idx:end_idx);
        
        % Fülle fehlende Daten mit letzten verfügbaren Werten auf
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
    
    % MPC-Optimierung durchführen
    [p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt] = ...
        mpc.computeControlAction(battery_energy_sim(k), pv_forecast_window, load_forecast_window);
    
    % Nur den ersten Steuerbefehl anwenden (Receding Horizon Prinzip)
    p_b_ch_applied(k) = p_b_ch_opt(1);
    p_b_dch_applied(k) = p_b_dch_opt(1);
    p_g_in_applied(k) = p_g_in_opt(1);
    p_g_out_applied(k) = p_g_out_opt(1);
    
    % Nettoleistung berechnen
    p_net_applied(k) = pv_forecast_window(1) - load_forecast_window(1);
    
    % Batteriezustand für nächsten Zeitschritt aktualisieren
    battery_energy_sim(k+1) = battery_energy_sim(k) + ...
                              nu_ch * p_b_ch_applied(k) * Ts + ...
                              (1/nu_dch) * p_b_dch_applied(k) * Ts - ...
                              L_bat * battery_energy_sim(k) * Ts;
    
    fprintf('SOC = %.2f kWh, p_bat = %.2f kW\n', battery_energy_sim(k+1), ...
            p_b_ch_applied(k) + p_b_dch_applied(k));
end

fprintf('Receding Horizon Simulation abgeschlossen.\n\n');

%% Berechnung der tatsächlichen Grid-Powers aus Energiebilanz
% Berechne p_g_net basierend auf Energiebilanz: p_g_net = p_in - p_b_ch - p_b_dch
% Positive Werte = Netzeinspeisung, Negative Werte = Netzbezug
p_g_out_energy_balance = zeros(1, N_sim);
p_g_in_energy_balance = zeros(1, N_sim);

for k = 1:N_sim
    % Grid-Net-Power aus Energiebilanz (überschreibt das preallocated Array)
    p_g_net_applied(k) = p_net_applied(k) - p_b_ch_applied(k) - p_b_dch_applied(k);
    
    % Aufteilung in Einspeisung und Bezug
    p_g_out_energy_balance(k) = max(0, p_g_net_applied(k));  % Positive = Einspeisung
    p_g_in_energy_balance(k) = min(0, p_g_net_applied(k));   % Negative = Bezug
end

fprintf('=== GRID-POWER VERGLEICH ===\n');
fprintf('Optimizer vs. Energiebilanz für erste 5 Zeitschritte:\n');
for i = 1:5
    fprintf('t=%d: Optimizer[in=%.3f, out=%.3f] vs. Energiebilanz[net=%.3f, in=%.3f, out=%.3f]\n', ...
        i, p_g_in_applied(i), p_g_out_applied(i), p_g_net_applied(i), ...
        p_g_in_energy_balance(i), p_g_out_energy_balance(i));
end
fprintf('============================\n\n');

%% Erste Optimierung für Vergleich (gesamter Horizont auf einmal)
fprintf('Führe Vergleichs-Optimierung über gesamten Horizont durch...\n');
[p_b_ch_opt_full, p_b_dch_opt_full, p_g_in_opt_full, p_g_out_opt_full] = ...
    mpc.computeControlAction(x_current, dummy_pv_extended(1:N_pred), dummy_load_extended(1:N_pred));

disp('Erste 5 optimale Werte (Vollhorizont):');
disp('Batterieladeleistung:');
disp(p_b_ch_opt_full(1:5));
disp('Batterieentladeleistung:'); 
disp(p_b_dch_opt_full(1:5));
disp('Netzbezugsleistung:');
disp(p_g_in_opt_full(1:5));

%% Plotting der Ergebnisse

% Zeitvektor für Simulation
t_sim = (0:N_sim-1) * Ts;
t_full = (0:N_pred-1) * Ts;

% Figure 2: Erweiterte Vorhersagen
figure;
subplot(2,1,1);
plot(t_extended, dummy_pv_extended, 'LineWidth', 2, 'Color', [1 0.5 0]);
xlabel('Zeit [h]');
ylabel('PV-Leistung [kW]');
title('Erweiterte PV-Vorhersage (3 Tage)');
grid on;
xlim([0 max(t_extended)]);

subplot(2,1,2);
plot(t_extended, dummy_load_extended, 'LineWidth', 2, 'Color', 'blue');
xlabel('Zeit [h]');
ylabel('Last [kW]');
title('Erweiterte Last-Vorhersage (3 Tage)');
grid on;
xlim([0 max(t_extended)]);

% Figure 3: System-Übersicht (Batteriesteuerung, PV-Produktion und Last mit Grid-Net)
figure;

% Subplot 1: Batteriesteuerung (Laden/Entladen kombiniert)
subplot(3,1,1);
plot(t_sim, p_b_ch_applied + p_b_dch_applied, 'LineWidth', 2, 'Color', 'g', 'DisplayName', 'Netto-Batteriesteuerung');
xlabel('Zeit [h]');
ylabel('Leistung [kW]');
title('Batteriesteuerung');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

% Subplot 2: PV-Produktion
subplot(3,1,2);
% Extrahiere PV-Daten für Simulationszeitraum
pv_sim = dummy_pv_extended(1:N_sim);
plot(t_sim, pv_sim, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'PV-Produktion');
xlabel('Zeit [h]');
ylabel('PV-Leistung [kW]');
title('PV-Produktion');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

% Subplot 3: Last und Grid-Net-Power
subplot(3,1,3);
% Extrahiere Last-Daten für Simulationszeitraum
load_sim = dummy_load_extended(1:N_sim);
plot(t_sim, load_sim, 'LineWidth', 2, 'Color', 'blue', 'DisplayName', 'Last');
hold on;
plot(t_sim, p_g_net_applied, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net-Power');
yline(0, 'k--', 'Alpha', 0.5, 'DisplayName', 'Nulllinie');
xlabel('Zeit [h]');
ylabel('Leistung [kW]');
title('Last und Grid-Net-Power (pos=Einspeisung, neg=Bezug)');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);
ylim([min([load_sim, p_g_net_applied])*1.1, max([load_sim, p_g_net_applied])*1.1]);

% Figure 4: Receding Horizon Simulation Ergebnisse
figure;

% Subplot 1: Batterieladeleistung
subplot(5,1,1);
plot(t_sim, p_b_ch_applied, 'LineWidth', 2, 'Color', 'green');
xlabel('Zeit [h]');
ylabel('[kW]');
title('Batterieladeleistung');
grid on;
xlim([0 max(t_sim)]);

% Subplot 2: Batterieentladeleistung
subplot(5,1,2);
plot(t_sim, p_b_dch_applied, 'LineWidth', 2, 'Color', 'red');
xlabel('Zeit [h]');
ylabel('[kW]');
title('Batterieentladeleistung');
grid on;
xlim([0 max(t_sim)]);

% Subplot 3: Netzbezugsleistung
subplot(5,1,3);
plot(t_sim, p_g_in_applied, 'LineWidth', 2, 'Color', 'blue');
xlabel('Zeit [h]');
ylabel('[kW]');
title('Netzbezugsleistung');
grid on;
xlim([0 max(t_sim)]);

% Subplot 4: Batterieenergie (State of Charge)
subplot(5,1,4);
plot((0:N_sim)*Ts, battery_energy_sim/E_bat, 'LineWidth', 2, 'Color', 'y');
hold on;
yline((1-DOD), '--r', 'LineWidth', 1.5, 'DisplayName', 'Min SOC');
xlabel('Zeit [h]');
ylabel('[%]');
title('Batterieenergie-Verlauf (State of Charge)');
legend('SOC', 'Min SOC', 'Max SOC', 'Location', 'best');
grid on;
xlim([0 max(t_sim)]);
ylim([min(battery_energy_sim)*0.9/E_bat, 1.1]);

% Subplot 5: Grid-Net-Power (aus Energiebilanz)
subplot(5,1,5);
plot(t_sim, p_g_net_applied, 'LineWidth', 2, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net (Energiebilanz)');
xlabel('Zeit [h]');
ylabel('[kW]');
title('Grid-Net-Power:');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);
ylim([min(p_g_net_applied)*1.1, max(p_g_net_applied)*1.1]);

% Figure 5: Grid-Power Aufschlüsselung
figure;

subplot(3,1,1);
plot(t_sim, p_net_applied, 'LineWidth', 2, 'Color', 'magenta', 'DisplayName', 'Net-Leistung (PV-Last)');
hold on;
plot(t_sim, p_b_ch_applied + p_b_dch_applied, 'LineWidth', 2, 'Color', 'black', 'DisplayName', 'Batteriesteuerung');
xlabel('Zeit [h]');
ylabel('Leistung [kW]');
title('Nettoleistung und Batteriesteuerung');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

subplot(3,1,2);
plot(t_sim, p_g_net_applied, 'LineWidth', 3, 'Color', [0.5 0 0.5], 'DisplayName', 'Grid-Net (Energiebilanz)');
hold on;
plot(t_sim, p_g_out_applied, 'LineWidth', 2, 'Color', 'green', 'DisplayName', 'Grid-Out (Optimizer)');
plot(t_sim, p_g_in_applied, 'LineWidth', 2, 'Color', 'red', 'DisplayName', 'Grid-In (Optimizer)');
yline(0, 'k--', 'Alpha', 0.5);
xlabel('Zeit [h]');
ylabel('Grid-Power [kW]');
title('Grid-Power Vergleich: Energiebilanz vs. Optimizer-Variablen');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

subplot(3,1,3);
plot(t_sim, p_g_out_energy_balance, 'LineWidth', 2, 'Color', [0.5 1 0.5], 'DisplayName', 'Einspeisung (aus p\_g\_net)');
hold on;
plot(t_sim, p_g_in_energy_balance, 'LineWidth', 2, 'Color', [1 0.5 0], 'DisplayName', 'Bezug (aus p\_g\_net)');
plot(t_sim, p_g_out_applied, '--', 'LineWidth', 1.5, 'Color', 'green', 'DisplayName', 'Einspeisung (Optimizer)');
plot(t_sim, p_g_in_applied, '--', 'LineWidth', 1.5, 'Color', 'red', 'DisplayName', 'Bezug (Optimizer)');
xlabel('Zeit [h]');
ylabel('Grid-Power [kW]');
title('Aufschlüsselung: Einspeisung vs. Bezug');
legend('Location', 'best');
grid on;
xlim([0 max(t_sim)]);

%% Zusammenfassung der Ergebnisse
fprintf('\n=== ZUSAMMENFASSUNG DER RECEDING HORIZON SIMULATION ===\n');
fprintf('Simulationsdauer: %.1f Stunden (%d Zeitschritte à %.0f min)\n', N_sim*Ts, N_sim, Ts*60);
fprintf('Vorhersagerhorizont: %.1f Stunden (%d Zeitschritte)\n', N_pred*Ts, N_pred);
fprintf('Anfängliche Batterieenergie: %.2f kWh\n', battery_energy_sim(1));
fprintf('Finale Batterieenergie: %.2f kWh\n', battery_energy_sim(end));
fprintf('Minimale Batterieenergie: %.2f kWh\n', min(battery_energy_sim));
fprintf('Maximale Batterieenergie: %.2f kWh\n', max(battery_energy_sim));
fprintf('Gesamte Batterieladung: %.2f kWh\n', sum(p_b_ch_applied) * Ts);
fprintf('Gesamte Batterieentladung: %.2f kWh\n', abs(sum(p_b_dch_applied)) * Ts);
fprintf('Gesamter Netzbezug: %.2f kWh\n', abs(sum(p_g_in_applied)) * Ts);
fprintf('Gesamte Netzeinspeisung: %.2f kWh\n', sum(p_g_out_applied) * Ts);
fprintf('\n--- ENERGIEBILANZ-BASIERTE GRID-POWER ---\n');
fprintf('Gesamter Netzbezug (Energiebilanz): %.2f kWh\n', abs(sum(p_g_in_energy_balance)) * Ts);
fprintf('Gesamte Netzeinspeisung (Energiebilanz): %.2f kWh\n', sum(p_g_out_energy_balance) * Ts);
fprintf('Grid-Net-Energy: %.2f kWh (pos=Einspeisung, neg=Bezug)\n', sum(p_g_net_applied) * Ts);
fprintf('Mittlere Grid-Net-Power: %.3f kW\n', mean(p_g_net_applied));
fprintf('Max Netzeinspeisung: %.2f kW\n', max(p_g_net_applied));
fprintf('Max Netzbezug: %.2f kW\n', min(p_g_net_applied));
fprintf('======================================================\n\n');

%% Demonstration: Vergleich Optimizer vs. Energiebilanz-Grid-Powers
fprintf('=== VERGLEICH: OPTIMIZER vs. ENERGIEBILANZ ===\n');
fprintf('Beispiel für ersten Zeitschritt:\n');

% Zeige ersten Zeitschritt der Vollhorizont-Optimierung
[p_b_ch_demo, p_b_dch_demo, p_g_in_opt_demo, p_g_out_opt_demo] = ...
    mpc.computeControlAction(x_current, dummy_pv_extended(1:N_pred), dummy_load_extended(1:N_pred));

% Berechne Grid-Powers manuell aus Energiebilanz
p_in_demo = dummy_pv_extended(1) - dummy_load_extended(1);
p_grid_net_demo = p_in_demo - p_b_ch_demo(1) - p_b_dch_demo(1);
p_g_out_manual = max(0, p_grid_net_demo);
p_g_in_manual = min(0, p_grid_net_demo);

fprintf('Optimizer Grid-Out: %.3f kW, Grid-In: %.3f kW\n', p_g_out_opt_demo(1), p_g_in_opt_demo(1));
fprintf('Energiebilanz Grid-Out: %.3f kW, Grid-In: %.3f kW\n', p_g_out_manual, p_g_in_manual);
fprintf('Netto-Grid-Power: %.3f kW (pos=Einspeisung, neg=Bezug)\n', p_grid_net_demo);
fprintf('Energiebilanz-Check: p_in(%.3f) = p_g_out(%.3f) + p_b_ch(%.3f) + p_b_dch(%.3f) + p_g_in(%.3f) = %.3f\n', ...
    p_in_demo, p_g_out_manual, p_b_ch_demo(1), p_b_dch_demo(1), p_g_in_manual, ...
    p_g_out_manual + p_b_ch_demo(1) + p_b_dch_demo(1) + p_g_in_manual);
fprintf('==========================================\n\n');

%