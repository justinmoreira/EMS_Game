import Dexie from "dexie";

export interface UserProgressRecord {
  id: string; // "self" for the local user
  tutorial_complete: boolean;
  updated_at: string;
  synced: boolean; // false = needs push to Supabase
}

export interface SandboxStateRecord {
  id: string; // "current" for the auto-saved live state, UUID for named slots
  name: string; // "" for "current", user-typed for named slots
  gamemode: string; // free-form mode tag ("sandbox", future: "mission", etc.)
  state_json: string; // serialized snapshot from BaseLevel.serialize_units()
  updated_at: string;
  synced: boolean;
}

class EmsDatabase extends Dexie {
  userProgress!: Dexie.Table<UserProgressRecord, string>;
  sandboxStates!: Dexie.Table<SandboxStateRecord, string>;

  constructor() {
    super("ems_game");
    this.version(1).stores({
      userProgress: "id, synced",
    });
    this.version(2).stores({
      userProgress: "id, synced",
      sandboxStates: "id, synced, updated_at",
    });
    // v3: + gamemode column. Backfill existing rows to "sandbox" so v2 users
    // upgrading don't see their saves vanish from the picker's mode filter.
    this.version(3)
      .stores({
        userProgress: "id, synced",
        sandboxStates: "id, synced, updated_at, gamemode",
      })
      .upgrade(async (tx) => {
        await tx
          .table<SandboxStateRecord, string>("sandboxStates")
          .toCollection()
          .modify((row) => {
            if (!row.gamemode) row.gamemode = "sandbox";
          });
      });
  }
}

export const db = new EmsDatabase();
