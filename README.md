# EMS PV Battery Simulation



> **Fair warning:** This code runs — under the right conditions, with the right data in the right folder. It is not production-grade. There is a lot of learning and debugging baked into every corner of this codebase. But with a little patience and curiosity you will get it running, and hopefully even understand what it is doing. Good luck and have fun 😉. 

---

## Overview

This project implements an **Energy Management System (EMS)** for a residential PV + battery storage setup. It compares two control strategies:

- **MPC Controller** — Model Predictive Control with a neural network load/PV forecast
- **Simple Controller** — A rule-based greedy strategy as baseline

The simulation is driven by real household measurement data and supports three house configurations (House E, House A with heat pump, House A without heat pump).

---

## Getting Started

### Prerequisites

- MATLAB (tested with R2024b / 2025)
- [YALMIP](https://yalmip.github.io/) toolbox (required for MPC optimisation)
- [MOSEK](https://www.mosek.com/) solver (used by YALMIP; free academic licence available)
- Deep Learning Toolbox (for loading the ONNX neural network predictor)

### Setting Up the Project

Open the MATLAB project file to ensure all dependencies and paths are correctly configured:

```
EMS_PV_Battery_Sim.prj
```

Simply double-click it in MATLAB, and the project will automatically:
- Add all source directories (`src/`, `predictor/`, etc.) to the MATLAB path
- Configure folder locations so that relative paths work correctly
- Set up any custom toolbox references

This avoids manual path configuration and ensures the code finds all data files and models consistently.

### Running the Simulation

The main entry point is [`src/controllers/main_run_sim_with_controller.m`](src/controllers/main_run_sim_with_controller.m).

Open it in MATLAB and adjust the configuration at the top of the script:

```matlab
% Time step (15 minutes)
Ts = 15/60;

% Prediction horizon (number of time steps)
N_pred = 48;

% Simulation window
start_date = datetime(2018, 9, 15, 0, 0, 0);
end_date   = datetime(2018, 9, 18, 0, 0, 0);

% House type: 'E', 'A_with' (with heat pump), or 'A_without'
house_type = 'A_without';
```

Then simply run the script. It will:
1. Load the pre-processed real measurement data for the selected house and time window
2. Initialise the MPC and Simple controllers with the battery parameters
3. Load the trained neural network predictor for the selected house type
4. Run both simulations step by step
5. Plot results and print electricity cost performance metrics

---

## Key Source Files

### [`src/controllers/EnergyManagementSimulation.m`](src/controllers/EnergyManagementSimulation.m)

The central simulation class. It orchestrates the entire simulation loop: loading real data, stepping through time, calling the controllers, updating battery state, storing history, and providing result structs for plotting. Both the MPC and Simple controller simulations are driven from here.

### [`src/controllers/MPC_Controller.m`](src/controllers/MPC_Controller.m)

Implements the Model Predictive Control strategy using YALMIP and MOSEK. At each time step it solves a Mixed-Integer Linear Programme (MILP) over the prediction horizon to minimise electricity cost, taking into account battery dynamics, grid constraints, time-of-use tariffs, and a peak power penalty. The forecast for PV and load is provided by the neural network predictor.

### [`src/controllers/simple_controller.m`](src/controllers/simple_controller.m)

A straightforward rule-based controller that serves as a baseline. It charges the battery when surplus PV power is available and discharges it when household demand exceeds PV generation, subject to battery capacity and power limits. No forecasting involved.

### [`src/predictor/NNPredictor.m`](src/predictor/NNPredictor.m)

Wraps a trained CNN-LSTM ONNX model to produce short-term load forecasts. It normalises the input features (time-of-day, day-of-year, temperature, historical load, etc.), runs inference, and returns a forecast sequence of the configured length (e.g. 48 steps = 12 hours ahead at 15-minute resolution).

---

## Data

### Source

The measurement data used in this project comes from the **RAPT dataset**, published alongside the paper:

> Holmberg, J. et al. (2020). *A Multi-Energy Dataset of Residential Buildings.*  
> Data, 5(1), 17. [https://www.mdpi.com/2306-5729/5/1/17](https://www.mdpi.com/2306-5729/5/1/17)

The raw HDF5 files can be downloaded from Zenodo:  
[https://zenodo.org/records/3581895](https://zenodo.org/records/3581895)

### Pre-processed Data

You do **not** need the raw `.hdf` files to run the simulation. The relevant data has already been extracted, smoothed to 15-minute intervals, and saved as `.mat` files in:

```
data/RAPT Dataset/matlab_datasets/
```

If you ever want to re-process the raw data yourself, see [`src/RAPT_data_extraction_to_mat.m`](src/RAPT_data_extraction_to_mat.m).

### Trained Prediction Models

The trained CNN-LSTM ONNX models used by `NNPredictor` are stored in:

```
predictor/models/
    house_A_without_HP/
    house_A_with_hp/
    house_E/
```

Each folder contains models for different prediction horizons (16, 24, 32, 48 steps). The correct model is loaded automatically based on `house_type` and `N_pred`.

---

## Project Structure

```
src/controllers/
    main_run_sim_with_controller.m   ← Start here
    EnergyManagementSimulation.m     ← Core simulation class
    MPC_Controller.m                 ← MPC with YALMIP/MOSEK
    simple_controller.m              ← Rule-based baseline
src/predictor/
    NNPredictor.m                    ← CNN-LSTM forecast wrapper
data/RAPT Dataset/matlab_datasets/   ← Pre-processed .mat data files
predictor/models/                    ← Trained ONNX models
```

