'use strict';

/**
 * @module shared/args
 *
 * CLI argument parser for the installed Claude Code workspace tool scripts.
 * Stub — replace with your workspace's actual implementation.
 */

/**
 * Parse process.argv into an options object.
 * Supports boolean flags (--flag) and key-value pairs (--key value, --key=value).
 * Unknown flags are silently ignored.
 *
 * @param {Object} defaults  Default values keyed by flag name
 * @returns {Object} Merged options (defaults overridden by CLI args)
 *
 * @example
 *   // node detect.js --json --verbose
 *   const opts = parseArgs({ json: false, verbose: false, notify: false });
 *   // => { json: true, verbose: true, notify: false }
 */
function parseArgs(defaults = {}) {
  const opts = { ...defaults };
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (!arg.startsWith('--')) continue;
    const eqIdx = arg.indexOf('=');
    if (eqIdx !== -1) {
      const key = arg.slice(2, eqIdx);
      if (key in opts) opts[key] = arg.slice(eqIdx + 1);
    } else {
      const key = arg.slice(2);
      if (key in opts) {
        if (typeof opts[key] === 'boolean') {
          opts[key] = true;
        } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          opts[key] = args[++i];
        }
      }
    }
  }
  return opts;
}

module.exports = { parseArgs };
