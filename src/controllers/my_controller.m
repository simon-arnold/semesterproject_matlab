close all


Ts = 15/60; % in Stunden
N_pred = 24/Ts; 

[dummy_pv_forecast, t] = linear_peak_series(5, 10, 7, 13, N_pred);
[dummy_load_forecast, t] = linear_peak_series(3, 21, 18, 23, N_pred);

figure;
plot(t, dummy_pv_forecast, 'LineWidth', 2)
hold on
plot(t, dummy_load_forecast, 'LineWidth', 2)
xlabel('Stunde')
ylabel('Wert [kW]')
title('Diskrete Peak-Zahlenreihe')
legend('PV-Vorhersage', 'Last-Vorhersage', 'Location', 'best')
grid on
xlim([0 24])

R_cost = diag([100, 100, 2000]); 
nu_ch = 0.85;
nu_dch = 0.95;
L_bat = 0;
E_bat = 3;
DOD = 0.4;
P_batconv_max = 1.8;
P_gridcons_max = 30;

mpc = MPC_Controller(24, N_pred, Ts, R_cost, nu_ch, nu_dch, L_bat, E_bat, DOD, P_batconv_max, P_gridcons_max);
x_current = 2.5; % Aktuelle Batteriekapazität in kWh (muss > 1.8 kWh sein)

[p_b_ch_opt, p_b_dch_opt, p_g_in_opt, p_g_out_opt] = mpc.computeControlAction(x_current, dummy_pv_forecast, dummy_load_forecast);

disp('Optimale Batterieladeleistung:');
disp(p_b_ch_opt(1:5)); % Zeige erste 5 Werte
disp('Optimale Batterieentladeleistung:'); 
disp(p_b_dch_opt(1:5)); % Zeige erste 5 Werte
disp('Optimale Netzbezugsleistung:');
disp(p_g_in_opt(1:5)); % Zeige erste 5 Werte

% Plotte die optimalen Steuergrößen
figure;

% Subplot 1: Batterieladeleistung
subplot(4,1,1);
plot(t, p_b_ch_opt, 'LineWidth', 2, 'Color', 'g');
xlabel('Zeit [h]');
ylabel('[kW]');
title('Optimale Batterieladeleistung');
grid on;
xlim([0 24]);

% Subplot 2: Batterieentladeleistung
subplot(4,1,2);
plot(t, p_b_dch_opt, 'LineWidth', 2, 'Color', 'r');
xlabel('Zeit [h]');
ylabel('[kW]');
title('Optimale Batterieentladeleistung');
grid on;
xlim([0 24]);

% Subplot 3: Netzbezugsleistung
subplot(4,1,3);
plot(t, p_g_in_opt, 'LineWidth', 2, 'Color', 'b');
xlabel('Zeit [h]');
ylabel('[kW]');
title('Optimale Netzbezugsleistung');
grid on;
xlim([0 24]);

% Subplot 4: Netzeinspeiseleistung
subplot(4,1,4);
plot(t, p_g_out_opt, 'LineWidth', 2, 'Color', 'm');
xlabel('Zeit [h]');
ylabel('[kW]');
title('Optimale Netzeinspeiseleistung');
grid on;
xlim([0 24]);

% Neuer Plot: Last-Vorhersage + Netzbezug + Batterieentladung
figure;
plot(t, dummy_load_forecast, 'LineWidth', 2, 'Color', 'g', 'DisplayName', 'Last-Vorhersage');
hold on;
plot(t, -p_g_in_opt, 'LineWidth', 2, 'Color', 'b', 'DisplayName', 'Netzbezug');
plot(t, -p_b_dch_opt, 'LineWidth', 2, 'Color', 'r', 'DisplayName', 'Batterieentladung');
xlabel('Zeit [h]');
ylabel('Leistung [kW]');
title('Lastdeckung: Last-Vorhersage vs. Energiequellen');
legend('Location', 'best');
grid on;
xlim([0 24]);

%