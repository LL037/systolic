# Systolic Array (PYNQ-Z2 bring-up)

This repository contains a small systolic-array-based MAC pipeline along with a simple board wrapper for the Digilent PYNQ-Z2.

## PYNQ-Z2 build notes

The PYNQ-Z2 wrapper is implemented in `src/top_pynq_z2.v` and expects:
- `clk125` from the on-board 125 MHz oscillator.
- `btn_start`, `btn_clear`, `btn_reset` push buttons.
- `led[3:0]` for status (busy + valid bits).

The constraints file `constraints/pynq_z2.xdc` maps these signals to the PYNQ-Z2 pins. Double-check the pinout against the Digilent master XDC for your board revision before generating a bitstream.

### Vivado flow (example)

1. Create a new RTL project targeting the PYNQ-Z2 (xc7z020clg400-1).
2. Add the Verilog sources from `src/`.
3. Set `src/top_pynq_z2.v` as the top module.
4. Add `constraints/pynq_z2.xdc` to the project.
5. Add `sim/input.mem` and `sim/weights.mem` as design sources so Vivado can initialize the inferred block RAMs (the RTL now references these paths directly).
6. Synthesize, implement, and generate the bitstream.

### Creating a design in Vivado (quick steps)

1. Open Vivado and select **Create Project**.
2. Choose **RTL Project**, and check **Do not specify sources at this time** if you prefer to add them afterward.
3. Select the part **xc7z020clg400-1** (PYNQ-Z2).
4. In **Project Manager → Add Sources**, add `src/*.v` plus `constraints/pynq_z2.xdc`.
5. In the same **Add Sources** flow, add `sim/input.mem` and `sim/weights.mem` as design sources (used to initialize BRAM).
6. Set `src/top_pynq_z2.v` as the top module, then run **Synthesis** and **Implementation**.

### Runtime behavior

- Press **btn_start** to kick off the pipeline (single pulse).
- Press **btn_clear** to clear all accumulators.
- **led[3]** shows `busy`, and **led[2:0]** show the lower three `valid_out` bits (adjust the LED mapping if you want all four valid bits).
