[y, t] = linear_peak_series(5, 15, 12, 18, 1440);
plot(t, y, 'LineWidth', 2)
xlabel('Stunde')
ylabel('Wert')
title('Diskrete Peak-Zahlenreihe')
grid on
xlim([0 24])
