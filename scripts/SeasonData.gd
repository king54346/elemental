class_name SeasonData
## Ported color configuration from the original SeasonManager (seasonConfigs) and
## Skydome (skyColors). All values are linear (THREE.Color(r,g,b) == linear); hex
## colors were converted. Keyed by season -> time -> component.

# Ground: light, dark, below(grass), rock, wshallow, wdeep
const GROUND := {
	"spring": {
		"day": {"light": Vector3(0.2784, 0.1372, 0.0235), "dark": Vector3(0.94, 0.58, 0.22), "below": Vector3(0.12, 0.15, 0.03), "rock": Vector3(1.0, 0.78, 0.47), "wshallow": Vector3(1.0, 0.4, 0.0), "wdeep": Vector3(0.06, 0.5, 0.51)},
		"night": {"light": Vector3(0.2, 0.1, 0.02), "dark": Vector3(0.804, 0.5411, 0.278), "below": Vector3(0.08, 0.1, 0.02), "rock": Vector3(0.7, 0.55, 0.33), "wshallow": Vector3(0.52, 0.207, 0.0), "wdeep": Vector3(0.03, 0.25, 0.3)},
	},
	"winter": {
		"day": {"light": Vector3(0.11, 0.39, 0.62), "dark": Vector3(0.85, 0.9, 0.95), "below": Vector3(0.65, 0.7, 0.75), "rock": Vector3(0.9, 0.95, 1.0), "wshallow": Vector3(0.7, 0.8, 0.95), "wdeep": Vector3(0.05, 0.28, 0.5)},
		"night": {"light": Vector3(0.5, 0.55, 0.6), "dark": Vector3(0.6, 0.65, 0.75), "below": Vector3(0.4, 0.45, 0.5), "rock": Vector3(0.7, 0.75, 0.85), "wshallow": Vector3(0.4, 0.5, 0.7), "wdeep": Vector3(0.15, 0.2, 0.4)},
	},
	"autumn": {
		"day": {"light": Vector3(0.45, 0.28, 0.15), "dark": Vector3(0.9, 0.65, 0.4), "below": Vector3(0.3, 0.2, 0.1), "rock": Vector3(0.95, 0.7, 0.5), "wshallow": Vector3(1.0, 0.49, 0.16), "wdeep": Vector3(0.07, 0.64, 0.72)},
		"night": {"light": Vector3(0.3, 0.2, 0.12), "dark": Vector3(0.7, 0.5, 0.35), "below": Vector3(0.2, 0.15, 0.08), "rock": Vector3(0.75, 0.55, 0.4), "wshallow": Vector3(0.58, 0.23, 0.0), "wdeep": Vector3(0.18, 0.83, 0.86)},
	},
	"rainy": {
		"day": {"light": Vector3(0.12, 0.054, 0.0), "dark": Vector3(0.93, 0.57, 0.21), "below": Vector3(0.039, 0.018, 0.0), "rock": Vector3(0.6, 0.5, 0.45), "wshallow": Vector3(0.47, 0.25, 0.07), "wdeep": Vector3(0.058, 0.39, 0.5)},
		"night": {"light": Vector3(0.15, 0.12, 0.1), "dark": Vector3(0.4, 0.35, 0.25), "below": Vector3(0.08, 0.12, 0.06), "rock": Vector3(0.45, 0.4, 0.35), "wshallow": Vector3(0.3, 0.4, 0.6), "wdeep": Vector3(0.08, 0.2, 0.3)},
	},
}

# Grass: shadow, dark, light, flower(visibility)
const GRASS := {
	"spring": {
		"day": {"shadow": Vector3(0.01, 0.16, 0.0), "dark": Vector3(0.0, 0.29, 0.02), "light": Vector3(0.48, 0.68, 0.007), "flower": 1.0},
		"night": {"shadow": Vector3(0.0023, 0.04, 0.0), "dark": Vector3(0.0, 0.23, 0.015), "light": Vector3(0.227, 0.31, 0.027), "flower": 0.15},
	},
	"winter": {
		"day": {"shadow": Vector3(0.2, 0.25, 0.29), "dark": Vector3(0.9, 0.9, 0.9), "light": Vector3(0.13, 0.32, 0.53), "flower": 0.2},
		"night": {"shadow": Vector3(0.005, 0.04, 0.08), "dark": Vector3(0.02, 0.15, 0.25), "light": Vector3(0.2, 0.35, 0.5), "flower": 0.05},
	},
	"autumn": {
		"day": {"shadow": Vector3(0.13, 0.062, 0.0039), "dark": Vector3(0.278, 0.019, 0.0), "light": Vector3(0.67, 0.498, 0.003), "flower": 0.9},
		"night": {"shadow": Vector3(0.05, 0.025, 0.01), "dark": Vector3(0.15, 0.1, 0.04), "light": Vector3(0.4, 0.3, 0.15), "flower": 0.15},
	},
	"rainy": {
		"day": {"shadow": Vector3(0.039, 0.018, 0.01), "dark": Vector3(0.015, 0.12, 0.0), "light": Vector3(0.0, 0.2, 0.031), "flower": 0.3},
		"night": {"shadow": Vector3(0.002, 0.06, 0.002), "dark": Vector3(0.015, 0.25, 0.03), "light": Vector3(0.25, 0.45, 0.2), "flower": 0.2},
	},
}

# Rocks: r1, r2, r3, m1, m2, m3
const ROCKS := {
	"spring": {
		"day": {"r1": Vector3(0.96, 0.86, 0.54), "r2": Vector3(0.97, 0.82, 0.42), "r3": Vector3(0.31, 0.24, 0.06), "m1": Vector3(0.97, 0.82, 0.42), "m2": Vector3(0.97, 0.82, 0.42), "m3": Vector3(0.14, 0.17, 0.003)},
		"night": {"r1": Vector3(0.7, 0.6, 0.35), "r2": Vector3(0.65, 0.55, 0.28), "r3": Vector3(0.2, 0.15, 0.04), "m1": Vector3(0.65, 0.55, 0.28), "m2": Vector3(0.65, 0.55, 0.28), "m3": Vector3(0.08, 0.1, 0.001)},
	},
	"winter": {
		"day": {"r1": Vector3(0.9, 0.95, 1.0), "r2": Vector3(0.85, 0.9, 0.95), "r3": Vector3(0.5, 0.55, 0.6), "m1": Vector3(0.7, 0.8, 0.9), "m2": Vector3(0.65, 0.75, 0.85), "m3": Vector3(0.3, 0.35, 0.4)},
		"night": {"r1": Vector3(0.7, 0.75, 0.8), "r2": Vector3(0.65, 0.7, 0.75), "r3": Vector3(0.35, 0.4, 0.45), "m1": Vector3(0.5, 0.6, 0.7), "m2": Vector3(0.45, 0.55, 0.65), "m3": Vector3(0.2, 0.25, 0.3)},
	},
	"autumn": {
		"day": {"r1": Vector3(0.95, 0.75, 0.55), "r2": Vector3(0.9, 0.7, 0.5), "r3": Vector3(0.5, 0.35, 0.2), "m1": Vector3(0.85, 0.6, 0.3), "m2": Vector3(0.8, 0.55, 0.25), "m3": Vector3(0.3, 0.2, 0.1)},
		"night": {"r1": Vector3(0.7, 0.55, 0.4), "r2": Vector3(0.65, 0.5, 0.35), "r3": Vector3(0.35, 0.25, 0.15), "m1": Vector3(0.6, 0.4, 0.2), "m2": Vector3(0.55, 0.35, 0.18), "m3": Vector3(0.2, 0.15, 0.08)},
	},
	"rainy": {
		"day": {"r1": Vector3(0.6, 0.55, 0.5), "r2": Vector3(0.55, 0.5, 0.45), "r3": Vector3(0.25, 0.22, 0.2), "m1": Vector3(0.039, 0.078, 0.0), "m2": Vector3(0.16, 0.25, 0.0), "m3": Vector3(0.0039, 0.19, 0.035)},
		"night": {"r1": Vector3(0.4, 0.38, 0.35), "r2": Vector3(0.35, 0.33, 0.3), "r3": Vector3(0.18, 0.15, 0.12), "m1": Vector3(0.2, 0.45, 0.15), "m2": Vector3(0.18, 0.4, 0.12), "m3": Vector3(0.08, 0.2, 0.05)},
	},
}

# Bush per type: shadow/mid/high/mult, tree(t*), birch(b*)
const BUSH := {
	"spring": {
		"day": {"shadow": Vector3(0.003, 0.074, 0.003), "mid": Vector3(0.06, 0.23, 0.0), "high": Vector3(0.44, 0.5, 0.0), "mult": Vector3(0.46, 0.65, 0.3), "tshadow": Vector3(0.03, 0.07, 0.003), "tmid": Vector3(0.06, 0.23, 0.0), "thigh": Vector3(0.45, 0.55, 0.002), "tmult": Vector3(0.77, 0.71, 0.35), "bshadow": Vector3(0.09, 0.03, 0.0), "bmid": Vector3(0.2, 0.03, 0.0), "bhigh": Vector3(1.0, 0.58, 0.1), "bmult": Vector3(0.68, 0.56, 0.22)},
		"night": {"shadow": Vector3(0.001, 0.03, 0.02), "mid": Vector3(0.02, 0.08, 0.05), "high": Vector3(0.15, 0.2, 0.15), "mult": Vector3(0.09, 0.13, 0.007), "tshadow": Vector3(0.01, 0.03, 0.001), "tmid": Vector3(0.04, 0.1, 0.005), "thigh": Vector3(0.2, 0.25, 0.05), "tmult": Vector3(0.25, 0.24, 0.001), "bshadow": Vector3(0.03, 0.015, 0.0), "bmid": Vector3(0.08, 0.015, 0.0), "bhigh": Vector3(0.3, 0.17, 0.03), "bmult": Vector3(0.3, 0.2, 0.01)},
	},
	"winter": {
		"day": {"shadow": Vector3(0.002, 0.04, 0.08), "mid": Vector3(0.01, 0.25, 0.16), "high": Vector3(0.8, 0.8, 0.8), "mult": Vector3(1.0, 1.0, 1.0), "tshadow": Vector3(0.01, 0.13, 0.26), "tmid": Vector3(0.015, 0.28, 0.27), "thigh": Vector3(0.73, 0.75, 0.78), "tmult": Vector3(0.8, 0.8, 0.8), "bshadow": Vector3(0.2, 0.09, 0.0), "bmid": Vector3(0.4, 0.2, 0.0), "bhigh": Vector3(0.8, 0.85, 0.9), "bmult": Vector3(0.7, 0.7, 0.7)},
		"night": {"shadow": Vector3(0.001, 0.02, 0.04), "mid": Vector3(0.02, 0.06, 0.12), "high": Vector3(0.15, 0.22, 0.35), "mult": Vector3(0.1, 0.15, 0.25), "tshadow": Vector3(0.01, 0.02, 0.04), "tmid": Vector3(0.04, 0.08, 0.15), "thigh": Vector3(0.2, 0.3, 0.4), "tmult": Vector3(0.25, 0.3, 0.4), "bshadow": Vector3(0.04, 0.05, 0.08), "bmid": Vector3(0.08, 0.1, 0.15), "bhigh": Vector3(0.35, 0.4, 0.5), "bmult": Vector3(0.3, 0.35, 0.45)},
	},
	"autumn": {
		"day": {"shadow": Vector3(0.12, 0.04, 0.001), "mid": Vector3(0.35, 0.15, 0.03), "high": Vector3(0.95, 0.6, 0.2), "mult": Vector3(0.85, 0.5, 0.25), "tshadow": Vector3(0.08, 0.05, 0.01), "tmid": Vector3(0.33, 0.05, 0.004), "thigh": Vector3(0.85, 0.63, 0.0), "tmult": Vector3(0.9, 0.6, 0.3), "bshadow": Vector3(0.09, 0.003, 0.004), "bmid": Vector3(0.21, 0.01, 0.0), "bhigh": Vector3(0.8, 0.317, 0.058), "bmult": Vector3(0.9, 0.3, 0.2)},
		"night": {"shadow": Vector3(0.0384, 0.0128, 0.00032), "mid": Vector3(0.112, 0.048, 0.0096), "high": Vector3(0.304, 0.192, 0.064), "mult": Vector3(0.272, 0.16, 0.08), "tshadow": Vector3(0.0256, 0.016, 0.0032), "tmid": Vector3(0.1056, 0.016, 0.00128), "thigh": Vector3(0.272, 0.2016, 0.0), "tmult": Vector3(0.288, 0.192, 0.096), "bshadow": Vector3(0.0288, 0.00096, 0.00128), "bmid": Vector3(0.0672, 0.0032, 0.0), "bhigh": Vector3(0.256, 0.10144, 0.01856), "bmult": Vector3(0.288, 0.096, 0.064)},
	},
	"rainy": {
		"day": {"shadow": Vector3(0.0, 0.019, 0.019), "mid": Vector3(0.011, 0.05, 0.007), "high": Vector3(0.102, 0.2, 0.019), "mult": Vector3(0.148, 0.405, 0.094), "tshadow": Vector3(0.0, 0.019, 0.019), "tmid": Vector3(0.011, 0.05, 0.007), "thigh": Vector3(0.102, 0.2, 0.019), "tmult": Vector3(0.148, 0.405, 0.094), "bshadow": Vector3(0.029, 0.027, 0.0), "bmid": Vector3(0.061, 0.027, 0.0), "bhigh": Vector3(0.19, 0.2, 0.01), "bmult": Vector3(0.68, 0.56, 0.22)},
		"night": {"shadow": Vector3(0.0, 0.017, 0.005), "mid": Vector3(0.004, 0.046, 0.013), "high": Vector3(0.029, 0.114, 0.04), "mult": Vector3(0.018, 0.074, 0.002), "tshadow": Vector3(0.002, 0.017, 0.0), "tmid": Vector3(0.008, 0.057, 0.002), "thigh": Vector3(0.038, 0.143, 0.013), "tmult": Vector3(0.048, 0.137, 0.0), "bshadow": Vector3(0.006, 0.009, 0.0), "bmid": Vector3(0.015, 0.009, 0.0), "bhigh": Vector3(0.14, 0.15, 0.0), "bmult": Vector3(0.48, 0.36, 0.02)},
	},
}

# Sky: zenith, horizon, ground, sun, sunglow (day) / moon, moonglow, star (night)
const SKY := {
	"spring": {
		"day": {"zenith": Vector3(0.0, 0.35, 0.82), "horizon": Vector3(0.46, 0.74, 0.93), "ground": Vector3(0.04, 0.55, 0.65), "sun": Vector3(0.639, 0.494, 0.058), "sunglow": Vector3(1.0, 0.635, 0.0)},
		"night": {"zenith": Vector3(0.02, 0.05, 0.15), "horizon": Vector3(0.05, 0.1, 0.25), "ground": Vector3(0.1, 0.15, 0.3), "moon": Vector3(0.95, 0.95, 1.0), "moonglow": Vector3(0.451, 0.557, 0.769), "star": Vector3(1.0, 1.0, 1.0)},
	},
	"winter": {
		"day": {"zenith": Vector3(0.4, 0.6, 0.9), "horizon": Vector3(0.8, 0.85, 0.95), "ground": Vector3(0.9, 0.92, 0.98), "sun": Vector3(0.95, 0.95, 1.0), "sunglow": Vector3(0.8, 0.9, 1.0)},
		"night": {"zenith": Vector3(0.01, 0.03, 0.12), "horizon": Vector3(0.03, 0.08, 0.2), "ground": Vector3(0.08, 0.12, 0.25), "moon": Vector3(1.0, 1.0, 1.0), "moonglow": Vector3(0.8, 0.9, 1.0), "star": Vector3(0.9, 0.95, 1.0)},
	},
	"autumn": {
		"day": {"zenith": Vector3(0.6, 0.4, 0.2), "horizon": Vector3(0.35, 0.66, 0.72), "ground": Vector3(1.0, 0.7, 0.4), "sun": Vector3(0.89, 0.75, 0.06), "sunglow": Vector3(0.94, 0.53, 0.0)},
		"night": {"zenith": Vector3(0.08, 0.04, 0.08), "horizon": Vector3(0.15, 0.08, 0.12), "ground": Vector3(0.25, 0.15, 0.2), "moon": Vector3(1.0, 0.5, 0.21), "moonglow": Vector3(0.898, 0.647, 0.365), "star": Vector3(1.0, 0.9, 0.8)},
	},
	"rainy": {
		"day": {"zenith": Vector3(0.25, 0.3, 0.4), "horizon": Vector3(0.4, 0.5, 0.6), "ground": Vector3(0.5, 0.6, 0.7), "sun": Vector3(0.7, 0.7, 0.8), "sunglow": Vector3(0.6, 0.6, 0.7)},
		"night": {"zenith": Vector3(0.03, 0.05, 0.08), "horizon": Vector3(0.06, 0.1, 0.15), "ground": Vector3(0.1, 0.15, 0.2), "moon": Vector3(0.6, 0.7, 0.8), "moonglow": Vector3(0.5, 0.6, 0.8), "star": Vector3(0.7, 0.8, 0.9)},
	},
}

const SEASON_INDEX := {"spring": 0, "winter": 1, "autumn": 2, "rainy": 3}

# WindLines color per season
const WINDLINE := {
	"spring": Vector3(1.0, 1.0, 1.0),
	"winter": Vector3(0.941, 0.973, 1.0),
	"autumn": Vector3(1.0, 0.918, 0.839),
	"rainy": Vector3(0.941, 0.957, 1.0),
}

# Falling leaves color per season
const LEAF := {
	"spring": Vector3(1.0, 0.435, 0.051),
	"winter": Vector3(0.992, 0.584, 0.047),
	"autumn": Vector3(1.0, 0.388, 0.278),
	"rainy": Vector3(0.0, 0.349, 0.11),
}
