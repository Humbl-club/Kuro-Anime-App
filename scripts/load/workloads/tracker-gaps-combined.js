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
    "export-mal-id-lookup": 0.2, // W2
    "search-with-hidden-adult-count": 1, // W4
    "collection-up-next": 2, // W10
    "collection-series-membership": 1, // W6
    "collection-with-tags-and-lists": 5, // W9
  }),
});
