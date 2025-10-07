clear
clc
close all

filename = '.\data\RAPT Dataset\datasets\dfA_300s.hdf';

%% Load datasets
time_ns = h5read(filename, '/data/axis1');          % X-axis: Nanoseconds
values = h5read(filename, '/data/block0_values');   % Y-axis: 8 channels x N measurements
items = strtrim(h5read(filename, '/data/block0_items')); % Channel names

time_s = double(time_ns) / 1e9;                      
time_dt = datetime(time_s, 'ConvertFrom', 'posixtime'); 
time_dt.TimeZone = 'Europe/Zurich';                  

%% Shift start time  + filter 7 days

originalStart = time_dt(1);
n_month_shift = 12;
startTime = originalStart + calmonths(n_month_shift) + days(1); % To set start date of plot to monday
% Either dataset D: startTime = originalStart + calmonths(6); 
% Dataset A: startTime = originalStart + calmonths(12) + days(1); % To set start date of plot to monday
endTime = startTime + days(7);
idx = (time_dt >= startTime) & (time_dt <= endTime);
timeFiltered = time_dt(idx);
valuesFiltered = values(:, idx);

%% Moving Average Filter for 15-minute data
% We always take 3 points: [-5min, 0, +5min] centered on full 15min
time15 = datetime.empty(0,1);  
time15.TimeZone = 'Europe/Zurich'; 
values15 = [];

for k = 1:length(timeFiltered)
    t = timeFiltered(k);
    % Check if we are at xx:00, xx:15, xx:30, xx:45
    if ismember(minute(t), [0 15 30 45])
        % Time window: -5min, 0, +5min
        windowIdx = find(timeFiltered >= t-minutes(5) & timeFiltered <= t+minutes(5));
        if ~isempty(windowIdx)
            avgVals = mean(valuesFiltered(:, windowIdx), 2);
            
            time15(end+1,1) = t;
            values15(:,end+1) = avgVals;
        end
    end
end

%% Table for smoothed data
T15 = array2table(values15');
T15.Properties.VariableNames = items;
T15.Time = time15;
T15 = movevars(T15, 'Time', 'Before', 1);

% --- Clean up null bytes and spaces from variable names ---
vn = T15.Properties.VariableNames;

vn2 = cellfun(@(c) regexprep(c, sprintf('%c',0), ''), vn, 'UniformOutput', false);
vn2 = cellfun(@strtrim, vn2, 'UniformOutput', false);

vn2 = matlab.lang.makeValidName(vn2);
vn2 = matlab.lang.makeUniqueStrings(vn2);

T15.Properties.VariableNames = vn2;

%% Status output & plot data
fprintf('Smoothed 15-minute data (%d months later, 7 days):\n', n_month_shift);
fprintf('Start time: %s\n', char(time15(1)));
fprintf('End time:   %s\n', char(time15(end)));
disp('Channel names:');
disp(items);


figure;
plot(time15, values15');  
xlabel('Time');
ylabel('Power');
legend(items, 'Interpreter', 'none');
title('dfA\_300s smoothed to 15-minute averages');
grid on;

%summary(T15)

% Create filtered table for .mat file - only store A_total_cons_power & A_exp_power with time
T_filtered = table();
T_filtered.Time = T15.Time;
T_filtered.A_total_cons_power = T15.A_total_cons_power;
T_filtered.A_exp_power = T15.A_exp_power;

% Save to .mat file - only store the filtered data
save('.\data\RAPT Dataset\matlab_datasets\dfA_300s_3months_7days_15min.mat', 'T_filtered');
fprintf('Filtered data saved (A_total_cons_power & A_exp_power only).\n');

%summary(T_filtered)

% Plot filtered data
figure;
plot(T_filtered.Time, T_filtered.A_total_cons_power, 'LineWidth', 2, 'DisplayName', 'Total Consumption Power');
hold on;
plot(T_filtered.Time, T_filtered.A_exp_power, 'LineWidth', 2, 'DisplayName', 'Export Power');
xlabel('Time');
ylabel('Power [kW]');
title('Filtered RAPT Data: Consumption vs Export Power');
legend('Location', 'best');
grid on;
