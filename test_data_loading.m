%% Test Script: Load Real Data and Check Available Columns
% This script tests the data loading functionality and shows
% what data is available in the dfE_300s.mat file

clear; clc;

% Add paths
addpath(genpath('src'));

%% Load the MAT file directly to inspect it
data_path = fullfile('data', 'RAPT Dataset', 'matlab_datasets', 'dfE_300s.mat');

fprintf('=== Inspecting dfE_300s.mat ===\n\n');

if ~isfile(data_path)
    error('File not found: %s', data_path);
end

fprintf('Loading file: %s\n\n', data_path);
loaded = load(data_path);

% Display variables in the file
fprintf('Variables in the file:\n');
disp(whos('-file', data_path));

% Display column names
fprintf('\n=== Column Names ===\n');
if isfield(loaded, 'col_names')
    col_names = loaded.col_names;
    if iscell(col_names)
        for i = 1:length(col_names)
            fprintf('%d. %s\n', i, col_names{i});
        end
    else
        disp(col_names);
    end
else
    fprintf('col_names variable not found!\n');
end

% Display time range
fprintf('\n=== Time Range ===\n');
if isfield(loaded, 'time_datenum')
    time_full = datetime(loaded.time_datenum, 'ConvertFrom', 'datenum');
    fprintf('Start: %s\n', datestr(time_full(1)));
    fprintf('End: %s\n', datestr(time_full(end)));
    fprintf('Duration: %.1f days\n', days(time_full(end) - time_full(1)));
    fprintf('Number of timesteps: %d\n', length(time_full));
    
    % Calculate time step
    if length(time_full) > 1
        dt = time_full(2) - time_full(1);
        fprintf('Time step: %s (%.1f minutes)\n', char(dt), minutes(dt));
    end
else
    fprintf('time_datenum variable not found!\n');
end

% Display data dimensions
fprintf('\n=== Data Dimensions ===\n');
if isfield(loaded, 'data')
    fprintf('Data size: %d rows x %d columns\n', size(loaded.data, 1), size(loaded.data, 2));
    
    % Show first few rows of data
    fprintf('\n=== First 5 Rows of Data ===\n');
    if isfield(loaded, 'col_names')
        col_names_cell = cellstr(loaded.col_names);
        data_table_preview = array2table(loaded.data(1:min(5, size(loaded.data,1)), :), ...
            'VariableNames', col_names_cell);
        disp(data_table_preview);
    else
        disp(loaded.data(1:min(5, size(loaded.data,1)), :));
    end
else
    fprintf('data variable not found!\n');
end

%% Test the helper function
fprintf('\n\n=== Testing load_real_data Helper Function ===\n\n');

try
    % Pick a date range within the available data
    if isfield(loaded, 'time_datenum')
        time_full = datetime(loaded.time_datenum, 'ConvertFrom', 'datenum');
        
        % Use a 3-day period from the available data
        test_start = time_full(1);
        test_end = test_start + days(3);
        
        fprintf('Testing with date range:\n');
        fprintf('  Start: %s\n', datestr(test_start));
        fprintf('  End: %s\n', datestr(test_end));
        
        [data_table, time_vec] = load_real_data(test_start, test_end);
        
        fprintf('\nSuccess! Loaded %d timesteps\n', height(data_table));
        fprintf('Available columns in loaded table:\n');
        disp(data_table.Properties.VariableNames);
        
        % Test feature preparation
        fprintf('\n=== Testing prepare_predictor_features ===\n');
        try
            features = prepare_predictor_features(data_table, 1, 192);
            fprintf('Success! Features prepared:\n');
            feature_names = fieldnames(features);
            for i = 1:length(feature_names)
                fprintf('  %s: length=%d\n', feature_names{i}, length(features.(feature_names{i})));
            end
        catch ME
            fprintf('Error preparing features: %s\n', ME.message);
            fprintf('This might be because Load or Temperature column names are different.\n');
            fprintf('Check the column names above and update prepare_predictor_features.m accordingly.\n');
        end
    else
        fprintf('Cannot test: time_datenum not available\n');
    end
catch ME
    fprintf('Error testing load_real_data: %s\n', ME.message);
    fprintf('Stack trace:\n');
    for i = 1:length(ME.stack)
        fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
    end
end

fprintf('\n=== Test Complete ===\n');
