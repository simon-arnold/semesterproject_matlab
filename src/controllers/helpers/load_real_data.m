function [data_table, time_vec] = load_real_data(start_date, end_date, house_type,  varargin)
    % load_real_data Lädt reale Daten aus dfE_300s.mat für einen bestimmten Zeitraum
    %
    % Wichtig: Lädt automatisch zusätzliche historische Daten für NN-Predictor
    % und zusätzliche zukünftige Daten für Forecast-Fenster!
    %
    % Eingaben:
    %   start_date - Startdatum der Simulation als datetime oder datenum oder String
    %   end_date   - Enddatum der Simulation als datetime oder datenum oder String
    %   house_type - Haus-Typ ('E' oder 'A')
    %   varargin   - Optional:
    %                'HistoryLength', N (Standard: 192) - Anzahl historischer Zeitschritte VOR start_date
    %                'ForecastLength', M (Standard: 0) - Anzahl zusätzlicher Zeitschritte NACH end_date
    %
    % Ausgaben:
    %   data_table - Table mit allen Daten (inkl. Historie VOR start_date und Forecast NACH end_date!)
    %   time_vec   - Datetime-Vektor für den ausgewählten Zeitraum
    %
    % Hinweis:
    %   Die zurückgegebenen Daten beginnen 'HistoryLength' Zeitschritte vor start_date
    %   und enden 'ForecastLength' Zeitschritte nach end_date, um historische Daten
    %   für den NN-Predictor und Forecast-Daten für das MPC-Fenster bereitzustellen.
    %
    % Beispiel:
    %   [data, times] = load_real_data(datetime(2018,1,1,0,0,0), datetime(2018,1,7,23,45,0), ...
    %                                  'HistoryLength', 192, 'ForecastLength', 48);
    
    % Lade die MAT-Datei

    switch house_type
        case 'E'
            data_path = fullfile('data', 'RAPT Dataset', 'matlab_datasets', 'dfE_300s.mat');
        case 'A_with'
            data_path = fullfile('data', 'RAPT Dataset', 'matlab_datasets', 'dfA_300s_with_HP.mat');
        case 'A_without'
            data_path = fullfile('data', 'RAPT Dataset', 'matlab_datasets', 'dfA_300s_without_HP.mat');
        otherwise
            error('load_real_data:InvalidHouseType', ...
                'Ungültiger house_type: %s. Erwartet ''E'', ''A_with'' oder ''A_without''.', house_type);
    end
    
    if ~isfile(data_path)
        error('load_real_data:FileNotFound', ...
            'Datendatei nicht gefunden: %s', data_path);
    end
    
    % Parse optional arguments
    p = inputParser;
    addParameter(p, 'HistoryLength', 192, @isnumeric);  % Default: 2*24*4 = 192
    addParameter(p, 'ForecastLength', 0, @isnumeric);   % Default: 0 (keine zusätzlichen Forecast-Daten)
    parse(p, varargin{:});
    history_length = p.Results.HistoryLength;
    forecast_length = p.Results.ForecastLength;
    
    fprintf('Lade Daten aus %s...\n', data_path);
    fprintf('  Angeforderte Simulation: %s bis %s\n', datestr(start_date), datestr(end_date));
    fprintf('  Lade zusätzlich %d historische Zeitschritte für Predictor\n', history_length);
    fprintf('  Lade zusätzlich %d Forecast-Zeitschritte nach end_date\n', forecast_length);
    
    loaded = load(data_path);
    
    % Extrahiere Variablen
    if ~isfield(loaded, 'data') || ~isfield(loaded, 'col_names') || ~isfield(loaded, 'time_datenum')
        error('load_real_data:MissingVariables', ...
            'Erwartete Variablen (data, col_names, time_datenum) nicht in Datei gefunden');
    end
    
    data_matrix = loaded.data;
    col_names = loaded.col_names;
    time_datenum = loaded.time_datenum;
    
    % Konvertiere col_names zu cell array falls nötig
    if isstring(col_names)
        col_names = cellstr(col_names);
    end
    
    % Konvertiere time_datenum zu datetime
    time_full = datetime(time_datenum, 'ConvertFrom', 'datenum');
    
    % Konvertiere Eingabedaten zu datetime falls nötig
    if ischar(start_date) || isstring(start_date)
        start_date = datetime(start_date, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
    elseif isnumeric(start_date)
        start_date = datetime(start_date, 'ConvertFrom', 'datenum');
    end
    
    if ischar(end_date) || isstring(end_date)
        end_date = datetime(end_date, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
    elseif isnumeric(end_date)
        end_date = datetime(end_date, 'ConvertFrom', 'datenum');
    end
    
    % Berechne das tatsächliche Start- und Enddatum (mit Historie und Forecast)
    % Annahme: 15-Minuten-Intervalle, also history_length * 0.25 Stunden
    time_step_hours = 0.25;
    actual_start_date = start_date - hours(history_length * time_step_hours);
    actual_end_date = end_date + hours(forecast_length * time_step_hours);
    
    % Finde Indizes für den gewünschten Zeitraum (inkl. Historie und Forecast)
    idx = (time_full >= actual_start_date) & (time_full <= actual_end_date);
    
    if sum(idx) == 0
        error('load_real_data:NoDataInRange', ...
            'Keine Daten im Zeitraum %s bis %s gefunden.\nVerfügbarer Zeitraum: %s bis %s', ...
            datestr(actual_start_date), datestr(actual_end_date), ...
            datestr(time_full(1)), datestr(time_full(end)));
    end

    % --- Neue Prüfungen: stellen sicher, dass time_full und data_matrix kompatibel sind ---
    % time_full muss mit der Zeitdimension von data_matrix übereinstimmen
    if numel(time_full) ~= size(data_matrix,1)
        % falls data_matrix transponiert ist, korrigieren
        if numel(time_full) == size(data_matrix,2)
            data_matrix = data_matrix';
            warning('load_real_data:DataTransposed', 'data_matrix transponiert, damit Zeitdimension passt.');
        else
            error('load_real_data:TimeDataMismatch', ...
                'Länge von time_datenum (%d) stimmt nicht mit Zeilen von data (%d).', ...
                numel(time_full), size(data_matrix,1));
        end
    end
    % -------------------------------------------------------------------------------

    % Überprüfe, ob genug historische Daten verfügbar sind
    first_idx = find(idx, 1, 'first');
    sim_start_idx = find(time_full >= start_date, 1, 'first');
    actual_history = sim_start_idx - first_idx;
    
    if actual_history < history_length
        error('load_real_data:InsufficientHistory', ...
            'Nicht genügend historische Daten verfügbar.\n' + ...
            'Angefordert: %d, Verfügbar: %d', history_length, actual_history);
    end
    
    % Extrahiere Daten für den Zeitraum
    data_subset = data_matrix(idx, :);
    time_vec = time_full(idx);
    time_vec = time_vec(:); % sicherstellen: Spaltenvektor

    % Prüfe Spaltenanzahl vs. col_names
    if numel(col_names) ~= size(data_subset,2)
        error('load_real_data:ColNamesMismatch', ...
            'Anzahl Spalten in data (%d) stimmt nicht mit Länge col_names (%d).', ...
            size(data_subset,2), numel(col_names));
    end

    % Erstelle Table aus den Daten
    data_table = array2table(data_subset, 'VariableNames', col_names);

    % Sicherheitscheck: Anzahl Zeilen müssen übereinstimmen
    if height(data_table) ~= numel(time_vec)
        error('load_real_data:RowCountMismatch', ...
            'height(data_table) = %d, numel(time_vec) = %d (muss gleich sein).', ...
            height(data_table), numel(time_vec));
    end

    data_table.Time = time_vec;
    
    fprintf('Daten geladen:\n');
    fprintf('  Gesamtanzahl Zeitschritte: %d\n', height(data_table));
    fprintf('  Tatsächlicher Beginn: %s (inkl. %d Historie-Schritte)\n', ...
        datestr(time_vec(1)), history_length);
    fprintf('  Simulationsbeginn: %s (Index %d in Table)\n', ...
        datestr(start_date), actual_history + 1);
    fprintf('  Simulationsende (angefordert): %s\n', datestr(end_date));
    fprintf('  Tatsächliches Ende: %s (inkl. %d Forecast-Schritte)\n', ...
        datestr(time_vec(end)), forecast_length);
    fprintf('  Simulationsdauer: %d Zeitschritte\n', sum(time_vec >= start_date & time_vec <= end_date));
    
    % Zeige verfügbare Spalten
    fprintf('Verfügbare Spalten: %s\n', strjoin(col_names, ', '));
end
