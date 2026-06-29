export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      keep_alive: {
        Row: {
          id: number
          last_ping: string
        }
        Insert: {
          id: number
          last_ping?: string
        }
        Update: {
          id?: number
          last_ping?: string
        }
        Relationships: []
      }
      match_actions: {
        Row: {
          action: Json
          created_at: string
          match_id: string
          player_id: string
          turn_number: number
        }
        Insert: {
          action: Json
          created_at?: string
          match_id: string
          player_id: string
          turn_number: number
        }
        Update: {
          action?: Json
          created_at?: string
          match_id?: string
          player_id?: string
          turn_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "match_actions_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      match_results: {
        Row: {
          finished_at: string
          is_draw: boolean
          loser_id: string | null
          match_id: string
          winner_id: string | null
        }
        Insert: {
          finished_at?: string
          is_draw?: boolean
          loser_id?: string | null
          match_id: string
          winner_id?: string | null
        }
        Update: {
          finished_at?: string
          is_draw?: boolean
          loser_id?: string | null
          match_id?: string
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "match_results_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      matches: {
        Row: {
          created_at: string
          current_turn: number
          finished_at: string | null
          guest_id: string | null
          host_id: string | null
          id: string
          invite_code: string | null
          max_turns: number
          name: string
          seed: number
          status: string
          updated_at: string
          visibility: string
          winner_id: string | null
        }
        Insert: {
          created_at?: string
          current_turn?: number
          finished_at?: string | null
          guest_id?: string | null
          host_id?: string | null
          id: string
          invite_code?: string | null
          max_turns?: number
          name?: string
          seed: number
          status?: string
          updated_at?: string
          visibility?: string
          winner_id?: string | null
        }
        Update: {
          created_at?: string
          current_turn?: number
          finished_at?: string | null
          guest_id?: string | null
          host_id?: string | null
          id?: string
          invite_code?: string | null
          max_turns?: number
          name?: string
          seed?: number
          status?: string
          updated_at?: string
          visibility?: string
          winner_id?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          display_name: string
          draws: number
          games_played: number
          id: string
          losses: number
          updated_at: string
          wins: number
        }
        Insert: {
          created_at?: string
          display_name?: string
          draws?: number
          games_played?: number
          id: string
          losses?: number
          updated_at?: string
          wins?: number
        }
        Update: {
          created_at?: string
          display_name?: string
          draws?: number
          games_played?: number
          id?: string
          losses?: number
          updated_at?: string
          wins?: number
        }
        Relationships: []
      }
      sandbox_states: {
        Row: {
          created_at: string
          gamemode: string
          name: string
          slot_id: string
          state_json: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          gamemode?: string
          name?: string
          slot_id: string
          state_json: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          gamemode?: string
          name?: string
          slot_id?: string
          state_json?: Json
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_progress: {
        Row: {
          created_at: string
          tutorial_complete: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          tutorial_complete?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          tutorial_complete?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      finish_match: {
        Args: { p_match_id: string; p_winner_id: string }
        Returns: undefined
      }
      join_match: { Args: { p_id_or_code: string }; Returns: string }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

