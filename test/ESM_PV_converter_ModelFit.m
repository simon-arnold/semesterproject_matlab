% Fitting parameters for the converter efficiency map
% .........................................................................
%               ======================================
%               |   ______  _____ __  __             |
%               |  |  ____|/ ____|  \/  | .......... |
%               |  | |__  | (___ | \  / | Energy.... |
%               |  |  __|  \___ \| |\/| | Storage... |
%               |  | |____ ____) | |  | | Management |
%               |  |______|_____/|_|  |_| .......... |
%               |====================================|
%               |    Masterarbeit Maurus Zwahlen     |
%               |       Oct 2023 - May 2024          |
%               ======================================
% .........................................................................
% Script to copy the DC AV inverter efficiency maps from PV sol into the
% polynomial fit that is used in the ESM Simulation. 
% 
%   project as well as a git repository:
%   https://gitlab.ethz.ch/mazwahle/master_thesis.git

clc
clear
close all

%% Hardcode the efficiency points from PV Sol

Huaway_Converter_Efficiency_10K = [0, 0 ;
                                    5, 94.66;
                                    10, 96.96;
                                    20, 97.92;
                                    30, 98.24;
                                    50, 98.41;
                                    70, 98.39;
                                    100, 98.32] .* 0.01;

Huaway_Converter_Efficiency_12K = [0, 0 ;
                                    5, 95.44;
                                    10, 97.22;
                                    20, 98.11;
                                    30, 98.31;
                                    50, 98.41;
                                    75, 98.24;
                                    100, 98.15] .* 0.01;

Hoymils_800W_Solar_Inverter = [0, 0 ;
                                    5, 93.97;
                                    10, 94.65;
                                    20, 95.48;
                                    30, 95.87;
                                    50, 96.42;
                                    75, 96.27;
                                    100, 95.56] .* 0.01;


%% Define the searching algorithm

Data2Fit = Hoymils_800W_Solar_Inverter;
% Data2Fit = Huaway_Converter_Efficiency_12K;
% Data2Fit = Hoymils_800W_Solar_Inverter; 

x0 =[0.0201;
     0.0606;
     0.0366];

% Inequality constraints: A * x < b
A = [];
b = [];
% Equality constraints: A_eq * x = b_eq
A_eq = [];
b_eq = [];

% Lower and upper bound for optimization
lb = [0;0;0];
ub = [1;1;1];


opts = optimoptions('fmincon','Display','iter','OptimalityTolerance', 1e-10, ...
    'StepTolerance', 1e-10, 'MaxFunctionEvaluations', 500,...
    'MaxIterations', 50);

x = fmincon(@(x) ConverterEfficiencyModelFit(x,Data2Fit)...
    , x0, A, b, A_eq, b_eq, lb, ub, [], opts);

disp('Parameters for efficiency map:')
disp(x)

%% Plot results

P_plot = linspace(0,1,1000);

for i=1:length(P_plot)
    eta(i,1) = ConverterEfficiency(x,P_plot(i));
end

figure
plot(P_plot,eta,'LineWidth',2,'LineStyle','-')
hold on
plot(Data2Fit(:,1),Data2Fit(:,2),'*r--','LineWidth',2)
xlabel('Utilization')
ylabel('efficiency \eta')
grid on

figure
plot(P_plot,eta,'LineWidth',2,'LineStyle','-')
xlabel('Utilization')
ylabel('efficiency \eta')
grid on

%% Calculate mean of eta between 0.25 and 1
% Filter data points where P_plot is between 0.25 and 1
mask = P_plot >= 0.25 & P_plot <= 1.0;
P_filtered = P_plot(mask);
eta_filtered = eta(mask);

% Calculate mean efficiency in the range [0.25, 1]
eta_mean = mean(eta_filtered);

fprintf('\n=== Efficiency Analysis ===\n');
fprintf('Utilization range: [%.2f, %.2f]\n', min(P_filtered), max(P_filtered));
fprintf('Number of data points: %d\n', length(eta_filtered));
fprintf('Mean efficiency (eta): %.4f (%.2f%%)\n', eta_mean, eta_mean*100);
fprintf('Min efficiency in range: %.4f (%.2f%%)\n', min(eta_filtered), min(eta_filtered)*100);
fprintf('Max efficiency in range: %.4f (%.2f%%)\n', max(eta_filtered), max(eta_filtered)*100);
fprintf('Standard deviation: %.4f\n', std(eta_filtered));
fprintf('===========================\n');



%% Functions
function Cost = ConverterEfficiencyModelFit(x,PV_Sol_Values)
    
    % initialize eta:
    eta = zeros(size(PV_Sol_Values,1),1);
    for i=1:size(PV_Sol_Values,1)
        P = PV_Sol_Values(i,1);
        eta(i,1) = ConverterEfficiency(x,P);
    end

    % Cost is the quadratic distance from the PV Sol Values:
    Cost = (eta - PV_Sol_Values(:,2))' * (eta - PV_Sol_Values(:,2));

end

function eta = ConverterEfficiency(x,P)
K0 = x(1);
K1 = x(2);
K2 = x(3);

eta = P/(P + K0 + K1*P + K2 * P^2);
end