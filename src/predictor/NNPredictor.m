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
    end
    
    properties (Constant)
        FEATURE_ORDER = {'Year', 'tod_sin', 'tod_cos', 'weekday_sin', ...
                        'weekday_cos', 'doy_sin', 'doy_cos', 'Load'};
        DEFAULT_INPUT_LENGTH = 2 * 24 * 4;  % 2 Tage * 24 Stunden * 4 (15-min Intervalle)
    end
    
    methods
        function obj = NNPredictor(prediction_horizon, feature_names_to_normalize, min_vals, max_vals)
            % Konstruktor für NNPredictor
            %
            % Eingaben:
            %   prediction_horizon - Vorhersagehorizont (16, 24, 32, oder 48)
            %   feature_names_to_normalize - Cell Array mit Namen der zu normalisierenden Features
            %   min_vals - Struct mit Minimum-Werten für jedes Feature
            %   max_vals - Struct mit Maximum-Werten für jedes Feature
            %
            % Beispiel:
            %   feature_names = {'Year', 'Load'};
            %   min_vals = struct('Year', 2023, 'Load', 0);
            %   max_vals = struct('Year', 2024, 'Load', 100);
            %   predictor = NNPredictor(16, feature_names, min_vals, max_vals);
            
            valid_horizons = [16, 24, 32, 48];
            if ~ismember(prediction_horizon, valid_horizons)
                error('NNPredictor:InvalidHorizon', ...
                    'prediction_horizon muss 16, 24, 32 oder 48 sein. Erhalten: %d', prediction_horizon);
            end
            
            obj.prediction_horizon = prediction_horizon;
            obj.feature_names_to_normalize = feature_names_to_normalize;
            obj.min_vals = min_vals;
            obj.max_vals = max_vals;
            obj.input_seq_len = obj.DEFAULT_INPUT_LENGTH;
            
            
            obj.loadModel();
        end
        
        function loadModel(obj)
                      
            model_path = fullfile('predictor', 'models', 'house_E', ...
                sprintf('hor_%d', obj.prediction_horizon), 'cnn_lstm_forecaster.onnx');
            
            if ~isfile(model_path)
                error('NNPredictor:ModelNotFound', ...
                    'ONNX Modell nicht gefunden: %s', model_path);
            end
            

            try
                obj.net = importONNXNetwork(model_path, 'OutputLayerType', 'regression');
                fprintf('ONNX Modell erfolgreich geladen: %s\n', model_path);
            catch ME
                error('NNPredictor:LoadError', ...
                    'Fehler beim Laden des ONNX Modells: %s\nFehlermeldung: %s', ...
                    model_path, ME.message);
            end
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
        
        function forecast = predict(obj, input_data)
            % Macht eine Vorhersage basierend auf historischen Daten
            %
            % Eingaben:
            %   input_data - Struct oder Table mit Features als Felder/Spalten
            %                Jedes Feature muss ein Vektor der Länge input_seq_len sein
            %                Erwartete Features: 'Year', 'tod_sin', 'tod_cos', 
            %                'weekday_sin', 'weekday_cos', 'doy_sin', 'doy_cos', 'Load'
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
            input_tensor = permute(feature_matrix, [3, 1, 2]);  % [1, seq_len, num_features]
            
            % Konvertiere zu dlarray für Deep Learning Toolbox
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
