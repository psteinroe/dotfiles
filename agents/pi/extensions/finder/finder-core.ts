import { Type } from "typebox";

/** Internal schema implementation for the public Mapper profile. */
export const FinderParams = Type.Object({
  query: Type.String({
    description: [
      "Map WHERE/WHAT facts in the workspace, not a diagnosis or design request.",
      "Include optional scope hints (paths/directories), search hints (symbols/filenames/extensions/config clues), and the locations/evidence needed back (files, line ranges, symbols, tests, dependencies, or explicit call/data-flow anchors).",
      "Mapper uses read, grep, find, and ls only. Do not ask Mapper to explain WHY, judge correctness, identify root cause, compare designs, plan, recommend fixes, review, or decide what should change; Oracle analysis is required for those requests.",
      "Examples:",
      "- Code: 'Map where authentication is implemented under src/auth and src/api. Return the entrypoint, token/session symbols, related config/tests, and line-cited call-flow anchors.'",
      "- Personal: 'Locate my latest trip itinerary PDF and adjacent booking files, returning candidate paths and evidence.'",
    ].join("\n"),
  }),
});
