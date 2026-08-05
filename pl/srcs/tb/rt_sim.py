#!/usr/bin/env python3
"""Generate deterministic vectors for wrapper_tb.sv using only Python."""

import cmath
import math
import random
from pathlib import Path


def sint_to_hex(value, bits=16):
    return f"{int(value) & ((1 << bits) - 1):0{bits // 4}X}"


def quantize(value, frac_bits=15, total_bits=16):
    scale = 1 << frac_bits
    minimum = -(1 << (total_bits - 1))
    maximum = (1 << (total_bits - 1)) - 1
    return max(minimum, min(maximum, round(value * scale)))


def sinc(value):
    if value == 0:
        return 1.0
    return math.sin(math.pi * value) / (math.pi * value)


def fir_lowpass(num_taps, sample_rate_hz, cutoff_hz):
    cutoff = cutoff_hz / sample_rate_hz
    middle = (num_taps - 1) / 2
    taps = []
    for index in range(num_taps):
        offset = index - middle
        window = 0.54 - 0.46 * math.cos(2 * math.pi * index / (num_taps - 1))
        taps.append(2 * cutoff * sinc(2 * cutoff * offset) * window)
    scale = sum(taps)
    return [tap / scale for tap in taps]


def frac_delay_taps(frac_delay, num_taps):
    half = (num_taps - 1) // 2
    return [sinc(index - frac_delay) for index in range(-half, half + 1)]


def convolve_head(taps, samples):
    """Return the first len(samples) values of a causal linear convolution."""
    output = []
    for sample_index in range(len(samples)):
        value = 0j
        for tap_index in range(min(len(taps), sample_index + 1)):
            value += taps[tap_index] * samples[sample_index - tap_index]
        output.append(value)
    return output


def write_sample_hex(path, data, adc_format, tx_scale=1, rx_scale=1):
    with path.open("w", encoding="ascii") as stream:
        for sample in range(0, len(data), 2):
            for antenna in range(len(data[0]) - 1, -1, -1):
                first = data[sample][antenna]
                second = data[sample + 1][antenna]
                if adc_format:
                    i0 = sint_to_hex(quantize(first.real))
                    q0 = sint_to_hex(quantize(first.imag))
                    i1 = sint_to_hex(quantize(second.real))
                    q1 = sint_to_hex(quantize(second.imag))
                    stream.write(f"{q1}{q0}{i1}{i0}")
                else:
                    scale = rx_scale if antenna == 0 else tx_scale
                    i0 = sint_to_hex(quantize(first.real) * scale)
                    q0 = sint_to_hex(quantize(first.imag) * scale)
                    i1 = sint_to_hex(quantize(second.real) * scale)
                    q1 = sint_to_hex(quantize(second.imag) * scale)
                    stream.write(f"{i1}{q1}{i0}{q0}")
            stream.write(f",{int(sample + 2 >= len(data))}\n")


def rt_core(inputs, phase_tx, taps0_tx, taps1_tx, phase_rx, taps0_rx, taps1_rx):
    sample_count = len(inputs)
    antenna_count = len(inputs[0])
    output = [[0j for _ in range(antenna_count)] for _ in range(sample_count)]

    adc0 = [row[0] for row in inputs]
    for channel in range(7):
        fractional = convolve_head(taps0_tx[channel], adc0)
        phased = [phase_tx[channel] * value for value in fractional]
        filtered = convolve_head(taps1_tx[channel], phased)
        for sample, value in enumerate(filtered):
            output[sample][channel + 1] = value

    accumulator = [0j] * sample_count
    for channel in range(7):
        adc = [row[channel + 1] for row in inputs]
        fractional = convolve_head(taps0_rx[channel], adc)
        phased = [phase_rx[channel] * value for value in fractional]
        filtered = convolve_head(taps1_rx[channel], phased)
        accumulator = [left + right for left, right in zip(accumulator, filtered)]
    for sample, value in enumerate(accumulator):
        output[sample][0] = value

    return output


def write_phases_hex(path, phase_tx, phase_rx):
    with path.open("w", encoding="ascii") as stream:
        for phase in phase_tx + phase_rx:
            stream.write(
                f"{sint_to_hex(quantize(phase.imag))}"
                f"{sint_to_hex(quantize(phase.real))}\n"
            )


def write_memory_init_hex(path, taps0_tx, taps1_tx, taps0_rx, taps1_rx):
    with path.open("w", encoding="ascii") as stream:
        for channel_taps in taps0_tx:
            for tap in reversed(channel_taps):
                stream.write(f"{sint_to_hex(quantize(tap))}\n")

        # GainCrrtFir has 21 symmetric taps and accepts its 11 unique values.
        for channel_taps in taps1_tx:
            for tap in channel_taps[:11]:
                stream.write(f"{sint_to_hex(quantize(tap))}\n")

        for channel_taps in taps0_rx:
            for tap in reversed(channel_taps):
                stream.write(f"{sint_to_hex(quantize(tap))}\n")

        for channel_taps in taps1_rx:
            for tap in channel_taps[:11]:
                stream.write(f"{sint_to_hex(quantize(tap))}\n")


def main():
    sample_count = 512
    antenna_count = 8
    channel_count = 7
    fractional_taps = 51
    gain_taps = 21

    generator = random.Random(10)
    hex_dir = Path(__file__).resolve().parent / "hex"
    hex_dir.mkdir(parents=True, exist_ok=True)

    for test_index in range(5):
        inputs = [
            [
                complex(1 - 2 * generator.random(), 1 - 2 * generator.random()) / 8
                for _ in range(antenna_count)
            ]
            for _ in range(sample_count)
        ]

        if test_index == 1:
            taps0_tx = [[1.0] + [0.0] * (fractional_taps - 1)
                        for _ in range(channel_count)]
            taps1_tx = [[0.0] * 10 + [1.0] + [0.0] * 10
                        for _ in range(channel_count)]
            taps0_rx = [taps.copy() for taps in taps0_tx]
            taps1_rx = [taps.copy() for taps in taps1_tx]
            phase_tx = [1 + 0j] * channel_count
            phase_rx = [1 + 0j] * channel_count
        else:
            taps0_tx = [
                frac_delay_taps(0.1 * (channel + 1), fractional_taps)
                for channel in range(channel_count)
            ]
            taps0_rx = [
                frac_delay_taps(0.2 * (channel + 1), fractional_taps)
                for channel in range(channel_count)
            ]
            taps1_tx = [
                fir_lowpass(gain_taps, 100e6, 10e6)
                for _ in range(channel_count)
            ]
            taps1_rx = [
                fir_lowpass(gain_taps, 100e6, 20e6)
                for _ in range(channel_count)
            ]
            phase_tx = [
                cmath.exp(1j * generator.random()) for _ in range(channel_count)
            ]
            phase_rx = [
                cmath.exp(1j * generator.random()) for _ in range(channel_count)
            ]

        output = rt_core(
            inputs,
            phase_tx,
            taps0_tx,
            taps1_tx,
            phase_rx,
            taps0_rx,
            taps1_rx,
        )

        if test_index == 0:
            for sample in range(sample_count):
                output[sample][0] = sum(inputs[sample][1:])
                for channel in range(channel_count):
                    output[sample][channel + 1] = inputs[sample][0]

        suffix = f"{test_index:02d}"
        write_sample_hex(hex_dir / f"input_{suffix}.hex", inputs, adc_format=True)
        write_sample_hex(hex_dir / f"output_{suffix}.hex", output, adc_format=False)

        if test_index == 1:
            for factor in (2, 4, 8, 16):
                write_sample_hex(
                    hex_dir / f"output_tx_scale_{factor}.hex",
                    output,
                    adc_format=False,
                    tx_scale=factor,
                )
                write_sample_hex(
                    hex_dir / f"output_rx_scale_{factor}.hex",
                    output,
                    adc_format=False,
                    rx_scale=factor,
                )

            write_sample_hex(
                hex_dir / "output_scale_4_8.hex",
                output,
                adc_format=False,
                tx_scale=4,
                rx_scale=8,
            )

        write_phases_hex(hex_dir / f"phases_{suffix}.hex", phase_tx, phase_rx)
        write_memory_init_hex(
            hex_dir / f"memory_init_{suffix}.hex",
            taps0_tx,
            taps1_tx,
            taps0_rx,
            taps1_rx,
        )

    print(f"Generated simulation vectors in {hex_dir}")


if __name__ == "__main__":
    main()
