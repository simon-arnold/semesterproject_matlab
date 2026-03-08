function features = prepare_predictor_features(data_table, start_idx, seq_len)
    % prepare_predictor_features Extrahiert die 9 Features für NNPredictor aus data_table
    %
    % Eingaben:
    %   data_table - Table mit den geladenen realen Daten
    %   start_idx  - Startindex in der Tabelle
    %   seq_len    - Anzahl der Zeitschritte (Default: 192)
    %
    % Ausgabe:
    %   features - Struct mit den 9 Features als Spaltenvektoren
    %
    % Beispiel:
    %   features = prepare_predictor_features(data_table, 1, 192);
    
    if nargin < 3
        seq_len = 192;  % Default: 2 Tage * 24 Stunden * 4 (15-min Intervalle)
    end
    
    % Validiere Indizes
    if start_idx < 1 || start_idx + seq_len - 1 > height(data_table)
        error('prepare_predictor_features:InvalidRange', ...
            'Ungültiger Bereich: start_idx=%d, seq_len=%d, table_height=%d', ...
            start_idx, seq_len, height(data_table));
    end
    
    end_idx = start_idx + seq_len - 1;
    
    features = struct();
    
    % WICHTIG: Reihenfolge muss mit NNPredictor.FEATURE_ORDER übereinstimmen!
    required_features = {'Year', 'tod_sin', 'tod_cos', 'weekday_sin', ...
                        'weekday_cos', 'doy_sin', 'doy_cos', 'Temperature', 'Load'};
    
    for i = 1:numel(required_features)
        feature_name = required_features{i};
        
        if ~ismember(feature_name, data_table.Properties.VariableNames)
            error('prepare_predictor_features:MissingFeature', ...
                'Feature "%s" nicht in data_table gefunden.\nVerfügbare Spalten: %s', ...
                feature_name, strjoin(data_table.Properties.VariableNames, ', '));
        end
        
        features.(feature_name) = double(data_table.(feature_name)(start_idx:end_idx));
        
        features.(feature_name) = features.(feature_name)(:);
    end
    
    % fprintf('Features erfolgreich extrahiert: %d Zeitschritte\n', seq_len);
end
