import Dexie from "dexie";

export interface UserProgressRecord {
  id: string; // "self" for the local user
  tutorial_complete: boolean;
  updated_at: string;
  synced: boolean; // false = needs push to Supabase
}

class EmsDatabase extends Dexie {
  userProgress!: Dexie.Table<UserProgressRecord, string>;

  constructor() {
    super("ems_game");
    this.version(1).stores({
      userProgress: "id, synced",
    });
  }
}

export const db = new EmsDatabase();
