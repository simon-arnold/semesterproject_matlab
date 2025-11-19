classdef simple_controller < handle
    properties
        % MPC Parameters
        T_s         % Sampling Time/delta t

        
        % System Parameters
        % Battery System
        nu_ch       % charging efficiency
        nu_dch      % discharging efficiency
        E_bat       % battery capacity
        DOD         % Depth of Discharge

        % PV System
        nu_pv       % PV efficiency

        % Max Transmission Power
        P_batconv_max
        P_gridcons_max

    end
    
    methods
        function obj = simple_controller(T_s, nu_ch, nu_dch, E_bat, DOD, P_batconv_max, P_gridcons_max, nu_pv)
            % Konstruktor: System und MPC Parameter initialisieren
            obj.T_s = T_s;
            obj.nu_ch = nu_ch;
            obj.nu_dch = nu_dch;
            obj.E_bat = E_bat;
            obj.DOD = DOD;
            obj.P_batconv_max = P_batconv_max;
            obj.P_gridcons_max = P_gridcons_max;
            obj.nu_pv = nu_pv;

            disp('Simple Controller initialized.');
        end
        



        function [p_b_ch, p_b_dch] = computeControlAction(obj, current_battery_energy, pv_current, load_current)
            
            % Control logic for simple controller:
            % if excess PV power (pv_current - load_current > 0):
            %   charge battery with excess power (up to max charge power and battery capacity)

            % if deficit power (pv_forecast - load_forecast < 0):
            %   discharge battery to cover deficit (up to max discharge power and minimum battery capacity)

            % Grid power constraint gets ignored

            % TODO:ich glaube es sollte noch ein wirkungsgrad in die lade und entlade leistungs constraints rein

            p_in = pv_current * obj.nu_pv - load_current;

            if p_in > 0
                % Excess power available for charging
                available_charge_power = min(p_in, obj.P_batconv_max);
                max_charge_possible = (obj.E_bat - current_battery_energy) / (obj.T_s * obj.nu_ch); % kW

                p_b_ch = min(available_charge_power, max_charge_possible);
                p_b_dch = 0;

            elseif p_in < 0
                % Deficit power, discharge battery if possible
                available_discharge_power = min(-p_in, obj.P_batconv_max);
                max_discharge_possible = (current_battery_energy - obj.E_bat*(1 - obj.DOD)) / obj.T_s * obj.nu_dch; % kW

                p_b_dch = -min(available_discharge_power, max_discharge_possible);
                p_b_ch = 0;

            else
                % No excess or deficit power
                p_b_ch = 0;
                p_b_dch = 0;
            end

            %disp(['Simple Controller: p_b_ch = ', num2str(p_b_ch), ' kW, p_b_dch = ', num2str(p_b_dch), ' kW']);
        end
    end
end

