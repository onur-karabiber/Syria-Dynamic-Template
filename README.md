# Syria Dynamic Template for DCS World

This repository contains a modular, "living" mission template for the DCS World Syria map. 

To overcome the limitations of tracking binary `.miz` files in Git, the mission structure has been unpacked. This allows for proper version control, collaborative development, and seamless external script management without fighting the DCS Mission Editor (ME).

## Features

* **Living Environment:** Active civilian air traffic, airports, and routes utilizing the Civil Aircraft Mod and Random Air Traffic (RAT) scripts.
* **Populated Infrastructure:** Ugra Media's detailed airbases are populated with guards, patrols, and SAM defenses to fill the otherwise empty static structures.
* **Integrated Skynet IADS:** Seamless integration of Skynet IADS, operating alongside MOOSE and MIST frameworks.
* **Dynamic Scoring:** Built-in operational scoring for Departure/Approach, ROE adherence, and precision strikes. Includes integration of Bankler's CASE I recovery metrics.
* **Lightweight & Modular:** Functions like a dynamic campaign but remains lightweight. Set the date and weather, drop in your specific flight, and launch into an active theater.

## Repository Structure

* `src/`: Contains the unpacked raw mission files (`mission`, `options`, `warehouses`, `dictionary`, etc.). Git tracks the structural changes here.
* `scripts/`: Holds all external Lua scripts (MOOSE, Skynet, RAT, custom logic). 
* `build.py`: Python script used to pack the `src/` directory back into a playable `.miz` file.
* `build/`: The output directory for the compiled `.miz` file (ignored by Git).

## Development Workflow

### 1. Building the Mission
Whenever you need to test the mission in DCS or prepare it for a server, run the build script from the root directory:
```bash
python build.py