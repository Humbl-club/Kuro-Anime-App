"use strict";
// Named combined workload: the predeclared base mix at its absolute rate plus one explicit
// absolute rate per tracker-gap profile (guest traffic as an absolute rps, never a share).
// Each profile's own task adds its line here; keys must equal the profile registry
// (backend_workload.test.js "combined workload names every profile with an explicit rate").
module.exports = Object.freeze({
  name: "tracker-gaps-combined",
  baseRps: 20,
  profiles: Object.freeze({
    "status-with-date-fill": 0.4, // F3.1d
  }),
});
