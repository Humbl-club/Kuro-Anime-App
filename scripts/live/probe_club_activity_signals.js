#!/usr/bin/env node
"use strict";
const { getPublicProjectConfig } = require("../lib/project_config");
const { makeProbe, execute, bounded, requireDelivery } = require("./probe_support");

async function subscribe(p, client, account, table, filter, events, suffix) {
  const channel = client.channel(`probe-${suffix}-${p.runId}`).on("postgres_changes",
    { event: "*", schema: "public", table, filter }, (payload) => {
      events.push({ ...payload, receivedAt: new Date().toISOString(), observedTable: table,
        subscriberUserId: account.userId, observedFilter: filter });
      p.evidence[`${suffix}Events`] = events.length;
    });
  p.channels.push({ client, channel }); // Own it before a failed/never-acknowledged subscription.
  await bounded(() => new Promise((resolve, reject) => {
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") resolve();
      if (["CHANNEL_ERROR", "TIMED_OUT", "CLOSED"].includes(status)) reject(new Error(`subscribe ${suffix}: ${status}`));
    });
  }), `subscribe ${suffix}`, p.timeout, () => channel.unsubscribe());
  return channel;
}
async function waitUntil(predicate, milliseconds, label) {
  const end = Date.now() + milliseconds;
  while (!predicate()) {
    if (Date.now() >= end) throw new Error(`${label}: no matching event before deadline`);
    await new Promise((resolve) => setTimeout(resolve, Math.min(50, end - Date.now())));
  }
}
async function realtimeChecks(p, createClient, observationMs = 1500) {
  const owner = await p.provision("signal-owner");
  const member = await p.provision("signal-member");
  const outsider = await p.provision("signal-out");
  const created = await p.rpc(owner, "create_club", { p_name: `Probe ${p.runId}`.slice(0, 80), p_sharing_level: "status" });
  const clubId = created?.club_id;
  if (clubId) p.clubs.push(clubId);
  if (!clubId || !created.invite_code) throw new Error("create_club returned incomplete identity");
  await p.rpc(member, "join_club", { p_invite_code: created.invite_code });
  const clients = {};
  for (const [role, account] of Object.entries({ owner, member, outsider })) {
    // The SDK refreshes auth after every channel join. Keep the disposable
    // account token authoritative even though these clients have no Auth session.
    const client = createClient(p.url, p.anonKey, { accessToken: async () => account.token,
      auth: { persistSession: false, autoRefreshToken: false } });
    clients[role] = client;
    await bounded(() => client.realtime.setAuth(account.token), "Realtime auth", p.timeout);
  }
  const select = async (who) => {
    const rows = await p.must(`/rest/v1/club_activity_signals?club_id=eq.${clubId}&select=revision,changed_at`, { token: who.token });
    if (!Array.isArray(rows)) throw new Error("Signal SELECT returned malformed rows");
    return rows;
  };
  const before = await select(member);
  if (before.length !== 1) throw new Error("Member's initial activity signal missing");
  const hidden = await select(outsider);
  if (hidden.length) throw new Error("Outsider can read activity signal");
  const events = { owner: [], member: [], outsider: [], membership: [] };
  Object.assign(p.evidence, { clubId, memberEvents: 0, ownerEvents: 0, outsiderEvents: 0, membershipEvents: 0,
    subscriberIdentities: { owner: owner.userId, member: member.userId, outsider: outsider.userId },
    signalEvents: events,
    rls: { outsiderSelectHidden: true, beforeRevision: before[0].revision } });
  for (const [role, account] of Object.entries({ owner, member, outsider })) {
    await subscribe(p, clients[role], account, "club_activity_signals", `club_id=eq.${clubId}`, events[role], role);
  }
  await subscribe(p, clients.member, member, "club_membership_signals", `user_id=eq.${member.userId.toLowerCase()}`, events.membership, "membership");
  await p.rpc(owner, "create_club_rail", { p_club_id: clubId, p_title: "Probe positive control" });
  const after = await select(member);
  if (after.length !== 1 || Number(after[0].revision) <= Number(before[0].revision)) throw new Error("Activity revision did not increase");
  const revision = Number(after[0].revision);
  p.evidence.rls.afterRevision = after[0].revision;
  const delivered = (rows, expected) => rows.filter((event) => event.new?.club_id === clubId && Number(event.new?.revision) >= expected);
  await waitUntil(() => delivered(events.member, revision).length && delivered(events.owner, revision).length, p.timeout, "Member activity delivery");
  // Bounded negative observation uses the same mutation and an authorized positive control.
  await new Promise((resolve) => setTimeout(resolve, observationMs));
  const result = { clubId, rls: { outsiderSelectHidden: true, beforeRevision: before[0].revision, afterRevision: after[0].revision },
    memberEvents: delivered(events.member, revision).length, outsiderEvents: events.outsider.length };
  requireDelivery(result); // Revision evidence can never substitute for WebSocket delivery.
  await p.rpc(owner, "remove_club_member", { p_club_id: clubId, p_user_id: member.userId });
  await waitUntil(() => events.membership.some((event) => event.new?.club_id === clubId && event.new?.state === "removed"), p.timeout, "Own membership removal delivery");
  if ((await select(member)).length) throw new Error("Removed member still reads activity signal");
  await p.rpc(owner, "create_club_rail", { p_club_id: clubId, p_title: "Probe after removal" });
  const finalRows = await select(owner);
  if (finalRows.length !== 1 || Number(finalRows[0].revision) <= revision) throw new Error("Revocation positive-control revision missing");
  const finalRevision = Number(finalRows[0].revision);
  p.evidence.finalRevision = finalRevision;
  await waitUntil(() => delivered(events.owner, finalRevision).length, p.timeout, "Owner post-removal positive control");
  await new Promise((resolve) => setTimeout(resolve, observationMs));
  if (delivered(events.member, finalRevision).length || events.outsider.length) throw new Error("Unauthorized post-removal delivery");
  return { ...result, delivery: "PASS", membershipDelivery: "PASS", revocation: "PASS", negativeObservationMs: observationMs,
    nativeSubscriptionLifecycle: "NOT_RUN" };
}
async function run(options = {}) {
  const config = options.config || getPublicProjectConfig();
  const p = makeProbe(config, { ...options, adminKey: options.adminKey || process.env.SUPABASE_SERVICE_ROLE_KEY, limits: true });
  p.anonKey = config.anonKey;
  const createClient = options.createClient || require("@supabase/supabase-js").createClient;
  return execute(p, (probe) => realtimeChecks(probe, createClient, options.observationMs));
}
if (require.main === module) {
  run().then((report) => { console.log(JSON.stringify(report, null, 2)); process.exitCode = report.exitCode; })
    .catch((error) => { console.error(error.message); process.exitCode = 1; });
}
module.exports = { run, realtimeChecks, subscribe };
