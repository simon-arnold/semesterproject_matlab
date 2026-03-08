% Time series with random noise
%close all;
clc;
clear;

% Parameters
n_points = 500;
t = 1:n_points;  % Time vector

% Generate random noise time series with normrnd()
mu = 5;      % Mittelwert
sigma = 1;   % Standardabweichung
noise_data = normrnd(mu, sigma, 1, n_points);  % Normalverteilte Daten

% Alternative noise types:
% uniform_noise = rand(1, n_points) - 0.5;     % Uniform noise [-0.5, 0.5]
% scaled_noise = 2 * randn(1, n_points);       % Scaled Gaussian noise (std=2)
% standard_normal = normrnd(0, 1, 1, n_points); % Equivalent to randn()
% high_variance = normrnd(10, 5, 1, n_points);  % Higher mean and variance

% Plot the time series
figure;
plot(t, noise_data, 'b-', 'LineWidth', 1.5);
hold on;
plot(t, noise_data, 'ro', 'MarkerSize', 4);  % Add markers
grid on;
xlabel('Time Step');
ylabel('Amplitude');
title(sprintf('Normal Distributed Data (μ=%.1f, σ=%.1f, N=%d)', mu, sigma, n_points));
legend('Noise Signal', 'Data Points', 'Location', 'best');

% Add statistics
mean_val = mean(noise_data);
std_val = std(noise_data);

% Display statistics on plot
text(0.02, 0.95, sprintf('Mean: %.3f', mean_val), 'Units', 'normalized', ...
     'BackgroundColor', 'white', 'FontSize', 10, 'Color', 'black');
text(0.02, 0.88, sprintf('Std Dev: %.3f', std_val), 'Units', 'normalized', ...
     'BackgroundColor', 'white', 'FontSize', 10, 'Color', 'black');

% Print statistics to console
fprintf('=== Normal Distributed Data Statistics ===\n');
fprintf('Parameters: μ=%.1f, σ=%.1f\n', mu, sigma);
fprintf('Number of points: %d\n', n_points);
fprintf('Sample mean: %.4f (expected: %.1f)\n', mean_val, mu);
fprintf('Sample std dev: %.4f (expected: %.1f)\n', std_val, sigma);
fprintf('Min value: %.4f\n', min(noise_data));
fprintf('Max value: %.4f\n', max(noise_data));
fprintf('Range: %.4f\n', max(noise_data) - min(noise_data));
fprintf('Mean deviation: %.4f\n', abs(mean_val - mu));
fprintf('Std deviation: %.4f\n', abs(std_val - sigma));
fprintf('==========================================\n');