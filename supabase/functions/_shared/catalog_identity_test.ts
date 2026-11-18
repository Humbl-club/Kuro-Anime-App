import { assertEquals } from "jsr:@std/assert@1";
import { writeWithMALConflict } from "./catalog_identity.ts";

Deno.test("a conflicting MAL alias is omitted once, while other identities keep their owner", async () => {
  for (const medium of ["anime", "manga"] as const) {
    const calls: boolean[] = [];
    const metrics = { identityConflicts: 0 };
    const result = await writeWithMALConflict(medium, (omit) => {
      calls.push(omit);
      return Promise.resolve(omit ? { data: { id: 7 }, error: null } : {
        data: null, error: { code: "23505", message: `duplicate key violates ${medium}_mal_id_key` },
      });
    }, metrics);
    assertEquals(calls, [false, true]);
    assertEquals(result.data, { id: 7 });
    assertEquals(metrics.identityConflicts, 1);
  }
});

Deno.test("successful writes are one request; other failures and failed retries are not swallowed", async () => {
  for (const error of [null, { code: "23505", message: "anime_anilist_id_key" }, { code: "42501", message: "denied" }]) {
    let calls = 0;
    const result = await writeWithMALConflict("anime", () => {
      calls++;
      return Promise.resolve({ data: null, error });
    }, {});
    assertEquals(calls, 1);
    assertEquals(result.error, error);
  }
  let calls = 0;
  const failure = { code: "23505", message: "anime_mal_id_key" };
  const result = await writeWithMALConflict("anime", () => {
    calls++;
    return Promise.resolve({ data: null, error: failure });
  }, {});
  assertEquals(calls, 2);
  assertEquals(result.error, failure);
});
