classdef NNPredictor < handle
    % NNPredictor - Neural Network Predictor für Energielastvorhersage
    %
    % Diese Klasse lädt ein ONNX CNN-LSTM Modell und macht Vorhersagen
    % basierend auf historischen Zeitreihendaten mit verschiedenen Features.
    %
    % Verwendung:
    %   predictor = NNPredictor(prediction_horizon, feature_names, min_vals, max_vals);
    %   forecast = predictor.predict(input_data);
    %
    % Eigenschaften:
    %   prediction_horizon - Anzahl der Zeitschritte für die Vorhersage (16/24/32/48)
    %   net - Das geladene ONNX Netzwerk
    %   feature_names_to_normalize - Cell Array mit Namen der zu normalisierenden Features
    %   min_vals - Struct mit Minimum-Werten für die Normalisierung
    %   max_vals - Struct mit Maximum-Werten für die Normalisierung
    %   input_seq_len - Länge der Eingabesequenz (Standard: 2*24*4 = 192 Zeitschritte)
    
    properties (Access = public)
        prediction_horizon  % 16, 24, 32 oder 48
        net                 % ONNX Netzwerk
        feature_names_to_normalize  % Cell Array mit Feature-Namen
        min_vals            % Struct mit Min-Werten
        max_vals            % Struct mit Max-Werten
        input_seq_len       % Länge der Eingabesequenz (192)
        house_type          % Haus-Typ ('E' oder 'A')
    end
    
    properties (Constant)
        FEATURE_ORDER = {'Year', 'tod_sin', 'tod_cos', 'weekday_sin', ...
                    'weekday_cos', 'doy_sin', 'doy_cos', 'Temperature', 'Load'};
        DEFAULT_INPUT_LENGTH = 2 * 24 * 4;  % 2 Tage * 24 Stunden * 4 (15-min Intervalle)
    end
    
    methods
        function obj = NNPredictor(prediction_horizon, house_type)
            % Konstruktor für NNPredictor
            %
            % Eingaben:
            %   prediction_horizon - Vorhersagehorizont (16, 24, 32 oder 48)
            %
            % Hinweis:
            %   Die Normalisierungsparameter (Min/Max) und die Liste der
            %   zu skalierenden Features werden nicht mehr als Argumente
            %   übergeben, sondern aus der Datei
            %   `data\RAPT Dataset\matlab_datasets\min_max_scaler_params.mat`
            %   geladen. Erwartete Variablen in der MAT-Datei: `Min_Vals`,
            %   `Max_Vals`, `Scaled_Feature_Names`.

            valid_horizons = [16, 24, 32, 48];
            if ~ismember(prediction_horizon, valid_horizons)
                error('NNPredictor:InvalidHorizon', ...
                    'prediction_horizon muss 16, 24, 32 oder 48 sein. Erhalten: %d', prediction_horizon);
            end

            obj.prediction_horizon = prediction_horizon;
            obj.input_seq_len = obj.DEFAULT_INPUT_LENGTH;

            obj.house_type = house_type;

            % Lade Min/Max-Parameter und die Feature-Liste aus Datei
            obj.loadScalerParams();

            % Lade das ONNX Modell
            obj.loadModel();
        end
        
        function loadModel(obj)
            
            switch obj.house_type
                case 'E'
                    disp('Lade ONNX Modell für Haus Typ E');
                    model_path = fullfile('predictor','models','house_E', sprintf('hor_%d', obj.prediction_horizon), 'cnn_lstm_forecaster.onnx');
                case 'A_with'
                    disp('Lade ONNX Modell für Haus Typ A mit HP');
                    model_path = fullfile('predictor','models','house_A_with_hp', sprintf('hor_%d', obj.prediction_horizon), 'cnn_lstm_forecaster.onnx');
                case 'A_without'
                    disp('Lade ONNX Modell für Haus Typ A ohne HP');
                    model_path = fullfile('predictor','models','house_A_without_HP', sprintf('hor_%d', obj.prediction_horizon), 'cnn_lstm_forecaster.onnx');
                otherwise
                    error('NNPredictor:InvalidHouseType', 'Ungültiger house_type: %s. Erwartet ''E'', ''A_with'' oder ''A_without''.', obj.house_type);
            end

            % Einfache, eindeutige Implementierung: benutze importONNXNetwork
            if exist('importONNXNetwork','file') == 2
                try
                    % Versuche zuerst als dlnetwork, sonst Standardnetz
                    try
                        obj.net = importONNXNetwork(model_path, 'OutputLayerType', 'regression', 'TargetNetwork', 'dlnetwork');
                    catch
                        obj.net = importONNXNetwork(model_path, 'OutputLayerType', 'regression');
                    end
                    fprintf('ONNX Modell erfolgreich geladen (importONNXNetwork): %s\n', model_path);
                    return;
                catch ME
                    error('NNPredictor:ImportFailed', 'Fehler beim Laden des ONNX Modells: %s\nFehlermeldung: %s', model_path, ME.message);
                end
            else
                error('NNPredictor:MissingImport', ['Die Funktion importONNXNetwork ist nicht verfügbar. ', ...
                    'Installiere das Support‑Paket "Deep Learning Toolbox Converter for ONNX Model Format" oder verwende eine MATLAB-Version mit ONNX-Unterstützung.']);
            end
        end

        function loadScalerParams(obj)
            % Lädt Min/Max-Scaler-Parameter aus MAT-Datei (vereinfachte, klare Logik)

            switch obj.house_type
                case 'E'
                    disp('Lade Scaler-Parameter für Haus Typ E');
                    scaler_path = fullfile('data', 'RAPT Dataset', 'matlab_datasets', 'min_max_E', 'min_max_scaler_params.mat');
                case 'A_with'
                    disp('Lade Scaler-Parameter für Haus Typ A mit HP');
                    scaler_path = fullfile('data', 'RAPT Dataset', 'matlab_datasets', 'min_max_A_with_HP', 'min_max_scaler_params.mat');
                case 'A_without'
                    disp('Lade Scaler-Parameter für Haus Typ A ohne HP');
                    scaler_path = fullfile('data', 'RAPT Dataset', 'matlab_datasets', 'min_max_A_without_HP', 'min_max_scaler_params.mat');
                otherwise
                    error('NNPredictor:InvalidHouseType', 'Ungültiger house_type: %s. Erwartet ''E'', ''A_with'' oder ''A_without''.', obj.house_type);
            end

            scaler_mat_file = load(scaler_path);

            disp("scaler_mat_files:")
            disp(scaler_mat_file);

      

            obj.feature_names_to_normalize = scaler_mat_file.Scaled_Features_Names;
            obj.min_vals = struct();
            obj.max_vals = struct();

            num_features = length(scaler_mat_file.Scaled_Features_Names);
            
            for i = 1:num_features
                feature_name = scaler_mat_file.Scaled_Features_Names{i};

                obj.feature_names_to_normalize{i} = feature_name;
                obj.min_vals.(feature_name) = scaler_mat_file.Min_Vals(i);
                obj.max_vals.(feature_name) = scaler_mat_file.Max_Vals(i);
            end

            disp('feature_names_to_normalize:');
            disp(obj.feature_names_to_normalize);
            disp('min_vals:');
            disp(obj.min_vals);
            disp('max_vals:');
            disp(obj.max_vals);

            % error('Debug stop after loading scaler parameters.');

        end
        
        function normalized_data = normalizeFeatures(obj, data, feature_name)
            % Min-Max Normalisierung für ein Feature
            %
            % Eingaben:
            %   data - Datenvektor für ein Feature [seq_len x 1]
            %   feature_name - Name des Features (String)
            %
            % Ausgabe:
            %   normalized_data - Normalisierte Daten [seq_len x 1]
            
            if ~isfield(obj.min_vals, feature_name) || ~isfield(obj.max_vals, feature_name)
                error('NNPredictor:MissingScalerParams', ...
                    'Min/Max Werte für Feature "%s" nicht gefunden', feature_name);
            end
            
            min_val = obj.min_vals.(feature_name);
            max_val = obj.max_vals.(feature_name);
            
            % Vermeide Division durch Null
            if max_val == min_val
                warning('NNPredictor:ZeroRange', ...
                    'Min und Max sind identisch für Feature "%s". Setze auf 0.', feature_name);
                normalized_data = zeros(size(data));
            else
                % Min-Max Normalisierung: (x - min) / (max - min)
                normalized_data = (data - min_val) / (max_val - min_val);
            end
        end
        
        function denormalized_data = denormalizeOutput(obj, normalized_data, feature_name)
            % Rückskalierung von normalisierten Daten zu Original-Skala
            %
            % Eingaben:
            %   normalized_data - Normalisierte Daten [N x 1]
            %   feature_name - Name des Features (String), z.B. 'Load'
            %
            % Ausgabe:
            %   denormalized_data - Rückskalierte Daten [N x 1]
            
            if ~isfield(obj.min_vals, feature_name) || ~isfield(obj.max_vals, feature_name)
                error('NNPredictor:MissingScalerParams', ...
                    'Min/Max Werte für Feature "%s" nicht gefunden', feature_name);
            end
            
            min_val = obj.min_vals.(feature_name);
            max_val = obj.max_vals.(feature_name);
            
            % Rückskalierung: x_original = x_normalized * (max - min) + min
            denormalized_data = normalized_data * (max_val - min_val) + min_val;
        end
        
        function forecast = predict(obj, input_data)
            % Macht eine Vorhersage basierend auf historischen Daten
            %
            % Eingaben:
            %   input_data - Struct oder Table mit Features als Felder/Spalten
            %                Jedes Feature muss ein Vektor der Länge input_seq_len sein
            %                Erwartete Features: 'Year', 'tod_sin', 'tod_cos', 
            %                'weekday_sin', 'weekday_cos', 'doy_sin', 'doy_cos', 'Load', 'Temperature'
            %
            % Ausgabe:
            %   forecast - Vorhersagevektor [prediction_horizon x 1]
            %
            % Beispiel:
            %   data.Year = ones(192, 1) * 2024;
            %   data.tod_sin = sin(linspace(0, 4*pi, 192))';
            %   % ... (weitere Features)
            %   forecast = predictor.predict(data);
            
            obj.validateInputData(input_data);
            
            num_features = length(obj.FEATURE_ORDER);
            feature_matrix = zeros(obj.input_seq_len, num_features);
            
    
            for i = 1:num_features
                feature_name = obj.FEATURE_ORDER{i};
                
                
                if isstruct(input_data)
                    if ~isfield(input_data, feature_name)
                        error('NNPredictor:MissingFeature', ...
                            'Feature "%s" nicht in input_data gefunden', feature_name);
                    end
                    feature_data = input_data.(feature_name);
                elseif istable(input_data)
                    if ~ismember(feature_name, input_data.Properties.VariableNames)
                        error('NNPredictor:MissingFeature', ...
                            'Feature "%s" nicht in input_data gefunden', feature_name);
                    end
                    feature_data = input_data.(feature_name);
                else
                    error('NNPredictor:InvalidInputType', ...
                        'input_data muss ein Struct oder Table sein');
                end
                
                feature_data = feature_data(:);
                
                if ismember(feature_name, obj.feature_names_to_normalize)
                    feature_data = obj.normalizeFeatures(feature_data, feature_name);
                end
                
                feature_matrix(:, i) = feature_data;
            end
            
            % Bereite Input für ONNX Netzwerk vor
            % ONNX erwartet: [batch_size, seq_len, num_features]
            % Füge Batch-Dimension hinzu
            % disp('Feature Matrix Size:');
            % disp(size(feature_matrix));
            % feature_matrix: [seq_len x num_features]  (z.B. [192 x 9])
            num_features = size(feature_matrix,2);
            seq_len = size(feature_matrix,1);

            % Erzeuge Shape [C, B, T] = [num_features, 1, seq_len]
            input_tensor = reshape(feature_matrix', [num_features, 1, seq_len]);   % -> [9 x 1 x 192]
            input_dlarray = dlarray(single(input_tensor), 'CBT');  % C=Channel, B=Batch, T=Time
            

            try
                output_dlarray = predict(obj.net, input_dlarray);
                forecast = extractdata(output_dlarray);
                forecast = squeeze(forecast);  
                forecast = double(forecast(:));  
            catch ME
                error('NNPredictor:PredictionError', ...
                    'Fehler bei der Vorhersage: %s', ME.message);
            end
            
            % Rückskalierung des Outputs (das Netzwerk sagt 'Load' vorher)
            % Das Netzwerk gibt normalisierte Werte aus, die wir zurückskalieren müssen
            if ismember('Load', obj.feature_names_to_normalize)
                forecast = obj.denormalizeOutput(forecast, 'Load');
            end

            if length(forecast) ~= obj.prediction_horizon
                warning('NNPredictor:UnexpectedOutputSize', ...
                    'Erwartete Ausgabegröße: %d, Erhalten: %d', ...
                    obj.prediction_horizon, length(forecast));
            end
        end
        
        function validateInputData(obj, input_data)
            % Validiert die Eingabedaten
            
            for i = 1:length(obj.FEATURE_ORDER)
                feature_name = obj.FEATURE_ORDER{i};
                
                if isstruct(input_data)
                    has_feature = isfield(input_data, feature_name);
                    if has_feature
                        feature_length = length(input_data.(feature_name));
                    end
                elseif istable(input_data)
                    has_feature = ismember(feature_name, input_data.Properties.VariableNames);
                    if has_feature
                        feature_length = height(input_data);
                    end
                else
                    error('NNPredictor:InvalidInputType', ...
                        'input_data muss ein Struct oder Table sein');
                end
                
                if ~has_feature
                    error('NNPredictor:MissingFeature', ...
                        'Erforderliches Feature "%s" nicht gefunden', feature_name);
                end
                
                if feature_length ~= obj.input_seq_len
                    error('NNPredictor:InvalidLength', ...
                        'Feature "%s" hat falsche Länge. Erwartet: %d, Erhalten: %d', ...
                        feature_name, obj.input_seq_len, feature_length);
                end
            end
        end
    end
end
