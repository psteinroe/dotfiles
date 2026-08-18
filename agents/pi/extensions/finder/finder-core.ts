import { Type } from "typebox";

/** The public Finder input schema, preserved from pi-finder v1.5.8. */
export const FinderParams = Type.Object({
  query: Type.String({
    description: [
      "Describe the end goal for reconnaissance in the workspace (code + personal files), not just one missing location.",
      "Include: (1) the task or decision this should unblock, (2) optional scope hints if known (paths/directories), (3) search hints (keywords/identifiers/filenames/extensions/metadata clues), (4) the deliverable you want back (entrypoints, core files, line ranges, related config/tests/docs/examples, candidate paths, metadata), (5) what counts as enough found.",
      "Finder uses rg/fd/ls and read — do not request grep or find.",
      "Examples:",
      "- Code: 'Before I change authentication, map where it is implemented. Search under src/auth and src/api for login/auth/authenticate, and return the entrypoint, token/session handling, related config/tests, and line-cited anchors.'",
      "- Personal: 'In ~/Documents and ~/Desktop, find my latest trip itinerary PDF and any adjacent booking files, and list the top candidate paths with evidence.'",
    ].join("\n"),
  }),
});
