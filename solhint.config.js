// solhint.config.js
const base = require('@layerzerolabs/solhint-config');

module.exports = {
    extends: 'solhint:recommended',

    rules: {
        /* keep the LayerZero defaults */
        ...base.rules,

        /* ───────── additional project-specific overrides ───────── */
        // ignore “could be indexed” gas tips
        'gas-indexed-events': 'off',
        // allow long functions (splitting algorithms)
        'function-max-lines': 'off',
        // allow non-strict inequalities if intentional
        'gas-strict-inequalities': 'off',
        // optional: increase permitted line width
        'max-line-length': ['warn', 120],
    },
};
