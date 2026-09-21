export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      assignments: {
        Row: {
          created_at: string
          created_by: string
          decline_reason: string | null
          id: string
          last_reminder_at: string | null
          proposed_at: string | null
          reminder_count: number
          replaced_by: string | null
          responded_at: string | null
          shift_id: string
          station_id: string
          status: Database["public"]["Enums"]["assignment_status"]
          updated_at: string
          user_id: string
          was_available: boolean
        }
        Insert: {
          created_at?: string
          created_by: string
          decline_reason?: string | null
          id?: string
          last_reminder_at?: string | null
          proposed_at?: string | null
          reminder_count?: number
          replaced_by?: string | null
          responded_at?: string | null
          shift_id: string
          station_id: string
          status?: Database["public"]["Enums"]["assignment_status"]
          updated_at?: string
          user_id: string
          was_available?: boolean
        }
        Update: {
          created_at?: string
          created_by?: string
          decline_reason?: string | null
          id?: string
          last_reminder_at?: string | null
          proposed_at?: string | null
          reminder_count?: number
          replaced_by?: string | null
          responded_at?: string | null
          shift_id?: string
          station_id?: string
          status?: Database["public"]["Enums"]["assignment_status"]
          updated_at?: string
          user_id?: string
          was_available?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "assignments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_replaced_by_fkey"
            columns: ["replaced_by"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "shifts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          data: Json
          entity: string
          entity_id: string | null
          id: number
          station_id: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          data?: Json
          entity: string
          entity_id?: string | null
          id?: never
          station_id?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          data?: Json
          entity?: string
          entity_id?: string | null
          id?: never
          station_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_log_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      availabilities: {
        Row: {
          created_at: string
          date: string
          id: string
          set_by: string | null
          slot: Database["public"]["Enums"]["slot_type"]
          station_id: string
          status: Database["public"]["Enums"]["availability_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          date: string
          id?: string
          set_by?: string | null
          slot: Database["public"]["Enums"]["slot_type"]
          station_id: string
          status?: Database["public"]["Enums"]["availability_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          date?: string
          id?: string
          set_by?: string | null
          slot?: Database["public"]["Enums"]["slot_type"]
          station_id?: string
          status?: Database["public"]["Enums"]["availability_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "availabilities_set_by_fkey"
            columns: ["set_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "availabilities_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "availabilities_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      availability_preferences: {
        Row: {
          comment: string | null
          created_at: string
          id: string
          max_shifts: number | null
          max_weekends: number | null
          period_id: string
          station_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          comment?: string | null
          created_at?: string
          id?: string
          max_shifts?: number | null
          max_weekends?: number | null
          period_id: string
          station_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          comment?: string | null
          created_at?: string
          id?: string
          max_shifts?: number | null
          max_weekends?: number | null
          period_id?: string
          station_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "availability_preferences_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "availability_preferences_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "v_member_load"
            referencedColumns: ["period_id"]
          },
          {
            foreignKeyName: "availability_preferences_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "v_period_completion"
            referencedColumns: ["period_id"]
          },
          {
            foreignKeyName: "availability_preferences_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "availability_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      invitations: {
        Row: {
          accepted_at: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          role: Database["public"]["Enums"]["membership_role"]
          station_id: string
          token: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          email: string
          expires_at?: string
          id?: string
          invited_by: string
          role?: Database["public"]["Enums"]["membership_role"]
          station_id: string
          token?: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string
          role?: Database["public"]["Enums"]["membership_role"]
          station_id?: string
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invitations_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      memberships: {
        Row: {
          created_at: string
          disabled_at: string | null
          display_name: string | null
          id: string
          joined_at: string
          role: Database["public"]["Enums"]["membership_role"]
          skills: string[]
          station_id: string
          status: Database["public"]["Enums"]["membership_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          disabled_at?: string | null
          display_name?: string | null
          id?: string
          joined_at?: string
          role?: Database["public"]["Enums"]["membership_role"]
          skills?: string[]
          station_id: string
          status?: Database["public"]["Enums"]["membership_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          disabled_at?: string | null
          display_name?: string | null
          id?: string
          joined_at?: string
          role?: Database["public"]["Enums"]["membership_role"]
          skills?: string[]
          station_id?: string
          status?: Database["public"]["Enums"]["membership_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "memberships_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_outbox: {
        Row: {
          attempts: number
          channels: string[] | null
          created_at: string
          dedupe_key: string | null
          id: string
          last_error: string | null
          locked_until: string | null
          payload: Json
          processed_at: string | null
          recipients: Json
          result: Json | null
          station_id: string | null
          status: string
          type: Database["public"]["Enums"]["notification_type"]
        }
        Insert: {
          attempts?: number
          channels?: string[] | null
          created_at?: string
          dedupe_key?: string | null
          id?: string
          last_error?: string | null
          locked_until?: string | null
          payload?: Json
          processed_at?: string | null
          recipients: Json
          result?: Json | null
          station_id?: string | null
          status?: string
          type: Database["public"]["Enums"]["notification_type"]
        }
        Update: {
          attempts?: number
          channels?: string[] | null
          created_at?: string
          dedupe_key?: string | null
          id?: string
          last_error?: string | null
          locked_until?: string | null
          payload?: Json
          processed_at?: string | null
          recipients?: Json
          result?: Json | null
          station_id?: string | null
          status?: string
          type?: Database["public"]["Enums"]["notification_type"]
        }
        Relationships: [
          {
            foreignKeyName: "notification_outbox_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at: string
          data: Json
          delivered: boolean | null
          error: string | null
          id: string
          read_at: string | null
          sent_at: string | null
          station_id: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
          user_id: string
        }
        Insert: {
          body: string
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          data?: Json
          delivered?: boolean | null
          error?: string | null
          id?: string
          read_at?: string | null
          sent_at?: string | null
          station_id?: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
          user_id: string
        }
        Update: {
          body?: string
          channel?: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          data?: Json
          delivered?: boolean | null
          error?: string | null
          id?: string
          read_at?: string | null
          sent_at?: string | null
          station_id?: string | null
          title?: string
          type?: Database["public"]["Enums"]["notification_type"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      periods: {
        Row: {
          created_at: string
          deadline_at: string
          id: string
          locked_at: string | null
          month: number
          station_id: string
          status: Database["public"]["Enums"]["period_status"]
          updated_at: string
          year: number
        }
        Insert: {
          created_at?: string
          deadline_at: string
          id?: string
          locked_at?: string | null
          month: number
          station_id: string
          status?: Database["public"]["Enums"]["period_status"]
          updated_at?: string
          year: number
        }
        Update: {
          created_at?: string
          deadline_at?: string
          id?: string
          locked_at?: string | null
          month?: number
          station_id?: string
          status?: Database["public"]["Enums"]["period_status"]
          updated_at?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "periods_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string
          first_name: string
          id: string
          last_name: string
          locale: string
          phone: string | null
          push_enabled: boolean
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          first_name?: string
          id: string
          last_name?: string
          locale?: string
          phone?: string | null
          push_enabled?: boolean
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          first_name?: string
          id?: string
          last_name?: string
          locale?: string
          phone?: string | null
          push_enabled?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      push_tokens: {
        Row: {
          created_at: string
          device_label: string | null
          id: string
          last_seen_at: string
          platform: Database["public"]["Enums"]["push_platform"]
          token: string
          user_id: string
        }
        Insert: {
          created_at?: string
          device_label?: string | null
          id?: string
          last_seen_at?: string
          platform: Database["public"]["Enums"]["push_platform"]
          token: string
          user_id: string
        }
        Update: {
          created_at?: string
          device_label?: string | null
          id?: string
          last_seen_at?: string
          platform?: Database["public"]["Enums"]["push_platform"]
          token?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_tokens_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      schedules: {
        Row: {
          created_at: string
          created_by: string
          id: string
          period_id: string
          published_at: string | null
          station_id: string
          status: Database["public"]["Enums"]["schedule_status"]
          updated_at: string
          validated_at: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          period_id: string
          published_at?: string | null
          station_id: string
          status?: Database["public"]["Enums"]["schedule_status"]
          updated_at?: string
          validated_at?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          period_id?: string
          published_at?: string | null
          station_id?: string
          status?: Database["public"]["Enums"]["schedule_status"]
          updated_at?: string
          validated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "schedules_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "schedules_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "schedules_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "v_member_load"
            referencedColumns: ["period_id"]
          },
          {
            foreignKeyName: "schedules_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "v_period_completion"
            referencedColumns: ["period_id"]
          },
          {
            foreignKeyName: "schedules_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      shifts: {
        Row: {
          created_at: string
          date: string
          id: string
          required_count: number
          schedule_id: string
          slot: Database["public"]["Enums"]["slot_type"]
          station_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          date: string
          id?: string
          required_count?: number
          schedule_id: string
          slot: Database["public"]["Enums"]["slot_type"]
          station_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          date?: string
          id?: string
          required_count?: number
          schedule_id?: string
          slot?: Database["public"]["Enums"]["slot_type"]
          station_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "shifts_schedule_id_fkey"
            columns: ["schedule_id"]
            isOneToOne: false
            referencedRelation: "schedules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_schedule_id_fkey"
            columns: ["schedule_id"]
            isOneToOne: false
            referencedRelation: "v_schedule_progress"
            referencedColumns: ["schedule_id"]
          },
          {
            foreignKeyName: "shifts_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      stations: {
        Row: {
          created_at: string
          id: string
          name: string
          settings: Json
          slug: string
          timezone: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          settings?: Json
          slug: string
          timezone?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          settings?: Json
          slug?: string
          timezone?: string
          updated_at?: string
        }
        Relationships: []
      }
      stripe_events: {
        Row: {
          attempts: number
          error: string | null
          id: string
          processed_at: string | null
          received_at: string
          result: Json
          station_id: string | null
          status: string
          type: string
        }
        Insert: {
          attempts?: number
          error?: string | null
          id: string
          processed_at?: string | null
          received_at?: string
          result?: Json
          station_id?: string | null
          status?: string
          type: string
        }
        Update: {
          attempts?: number
          error?: string | null
          id?: string
          processed_at?: string | null
          received_at?: string
          result?: Json
          station_id?: string | null
          status?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "stripe_events_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      subscriptions: {
        Row: {
          created_at: string
          current_period_end: string | null
          plan: string | null
          station_id: string
          status: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id: string | null
          stripe_subscription_id: string | null
          suspended_at: string | null
          trial_ends_at: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          current_period_end?: string | null
          plan?: string | null
          station_id: string
          status?: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          suspended_at?: string | null
          trial_ends_at?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          current_period_end?: string | null
          plan?: string | null
          station_id?: string
          status?: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          suspended_at?: string | null
          trial_ends_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: true
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      super_admins: {
        Row: {
          created_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "super_admins_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      v_member_last_availability: {
        Row: {
          last_set_at: string | null
          station_id: string | null
          user_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "availabilities_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "availabilities_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      v_member_load: {
        Row: {
          accepted_previous: number | null
          max_shifts: number | null
          max_weekends: number | null
          month: number | null
          period_id: string | null
          shifts_count: number | null
          shifts_left: number | null
          station_id: string | null
          user_id: string | null
          weekend_units: number | null
          weekends_left: number | null
          year: number | null
        }
        Relationships: [
          {
            foreignKeyName: "memberships_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "periods_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      v_period_completion: {
        Row: {
          active_members: number | null
          members_with_availability: number | null
          month: number | null
          period_id: string | null
          station_id: string | null
          year: number | null
        }
        Relationships: [
          {
            foreignKeyName: "periods_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
      v_schedule_progress: {
        Row: {
          assignments_accepted: number | null
          assignments_declined: number | null
          assignments_late: number | null
          assignments_pending: number | null
          period_id: string | null
          schedule_id: string | null
          shifts_filled: number | null
          shifts_total: number | null
          station_id: string | null
          status: Database["public"]["Enums"]["schedule_status"] | null
        }
        Relationships: [
          {
            foreignKeyName: "schedules_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "schedules_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "v_member_load"
            referencedColumns: ["period_id"]
          },
          {
            foreignKeyName: "schedules_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "v_period_completion"
            referencedColumns: ["period_id"]
          },
          {
            foreignKeyName: "schedules_station_id_fkey"
            columns: ["station_id"]
            isOneToOne: false
            referencedRelation: "stations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      accept_invitation: {
        Args: { p_email: string; p_token: string; p_user_id: string }
        Returns: Json
      }
      assignment_reminder_targets: {
        Args: { p_instant?: string; p_palier: string; p_schedule: string }
        Returns: string[]
      }
      availability_matrix: {
        Args: { p_period: string; p_station: string }
        Returns: {
          accepted_previous: number
          comment: string
          day_slots: string
          display_name: string
          first_name: string
          last_name: string
          max_shifts: number
          max_weekends: number
          night_slots: string
          shifts_count: number
          shifts_left: number
          user_id: string
          weekend_units: number
          weekends_left: number
        }[]
      }
      cancel_assignment: {
        Args: { p_assignment: string; p_reason?: string }
        Returns: Json
      }
      create_invitation: {
        Args: {
          p_email: string
          p_invited_by: string
          p_role: Database["public"]["Enums"]["membership_role"]
          p_station: string
        }
        Returns: Json
      }
      create_period: {
        Args: { p_month: number; p_station: string; p_year: number }
        Returns: {
          created_at: string
          deadline_at: string
          id: string
          locked_at: string | null
          month: number
          station_id: string
          status: Database["public"]["Enums"]["period_status"]
          updated_at: string
          year: number
        }
        SetofOptions: {
          from: "*"
          to: "periods"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_schedule: {
        Args: { p_period: string; p_station: string }
        Returns: {
          created_at: string
          created_by: string
          id: string
          period_id: string
          published_at: string | null
          station_id: string
          status: Database["public"]["Enums"]["schedule_status"]
          updated_at: string
          validated_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "schedules"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cron_assignment_reminders: {
        Args: { p_reference?: string }
        Returns: number
      }
      cron_availability_reminders: {
        Args: { p_reference?: string }
        Returns: number
      }
      cron_create_periods: { Args: { p_reference?: string }; Returns: number }
      cron_dispatch_notifications: {
        Args: {
          p_limit?: number
          p_max_attempts?: number
          p_reference?: string
        }
        Returns: number
      }
      cron_late_responders_report: {
        Args: { p_reference?: string }
        Returns: number
      }
      cron_lock_periods: { Args: { p_reference?: string }; Returns: number }
      cron_subscription_reminders: {
        Args: { p_reference?: string }
        Returns: number
      }
      cron_suspend_subscriptions: {
        Args: { p_reference?: string }
        Returns: number
      }
      delete_own_account: { Args: { p_user_id: string }; Returns: Json }
      est_jour_ferie: { Args: { p_date: string }; Returns: boolean }
      is_admin: { Args: { p_station: string }; Returns: boolean }
      is_member: { Args: { p_station: string }; Returns: boolean }
      is_super_admin: { Args: never; Returns: boolean }
      jours_feries_fr: { Args: { p_annee: number }; Returns: string[] }
      mask_email: { Args: { p_email: string }; Returns: string }
      notification_outbox_recipients_valides: {
        Args: { p_recipients: Json }
        Returns: boolean
      }
      notify: {
        Args: {
          p_channels?: string[]
          p_dedupe_key?: string
          p_payload?: Json
          p_recipients?: Json
          p_station?: string
          p_type: Database["public"]["Enums"]["notification_type"]
          p_user_ids?: string[]
        }
        Returns: string
      }
      notify_claim: {
        Args: { p_outbox: string }
        Returns: {
          attempts: number
          channels: string[] | null
          created_at: string
          dedupe_key: string | null
          id: string
          last_error: string | null
          locked_until: string | null
          payload: Json
          processed_at: string | null
          recipients: Json
          result: Json | null
          station_id: string | null
          status: string
          type: Database["public"]["Enums"]["notification_type"]
        }
        SetofOptions: {
          from: "*"
          to: "notification_outbox"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      notify_complete: {
        Args: {
          p_error?: string
          p_ok: boolean
          p_outbox: string
          p_result?: Json
        }
        Returns: undefined
      }
      notify_endpoint: { Args: never; Returns: Record<string, unknown> }
      notify_internal_secret: { Args: never; Returns: string }
      notify_post: { Args: { p_outbox: string }; Returns: boolean }
      notify_trace_echec: { Args: { p_outbox: string }; Returns: string }
      paques_gregorien: { Args: { p_annee: number }; Returns: string }
      period_deadline_at: {
        Args: {
          p_deadline_day: number
          p_month: number
          p_timezone: string
          p_year: number
        }
        Returns: string
      }
      publish_schedule: {
        Args: { p_actor: string; p_schedule: string }
        Returns: Json
      }
      reassign_shift: {
        Args: {
          p_actor: string
          p_previous?: string
          p_shift: string
          p_user: string
        }
        Returns: Json
      }
      remind_schedule: {
        Args: { p_schedule: string; p_tout?: boolean }
        Returns: Json
      }
      schedule_complet: { Args: { p_schedule: string }; Returns: boolean }
      schedule_reevaluer: { Args: { p_schedule: string }; Returns: boolean }
      station_access: { Args: { p_station: string }; Returns: Json }
      station_required_count: {
        Args: {
          p_date: string
          p_settings: Json
          p_slot: Database["public"]["Enums"]["slot_type"]
        }
        Returns: number
      }
      station_settings_cle_surcharge_valide: {
        Args: { p_cle: string }
        Returns: boolean
      }
      station_settings_entier_valide: {
        Args: { p_max: number; p_min: number; p_valeur: Json }
        Returns: boolean
      }
      station_settings_heure_valide: {
        Args: { p_valeur: Json }
        Returns: boolean
      }
      station_settings_valid: { Args: { p_settings: Json }; Returns: boolean }
      station_slug: { Args: { p_name: string }; Returns: string }
      station_writable: { Args: { p_station: string }; Returns: boolean }
      stripe_event_close: {
        Args: { p_code: string; p_event_id: string; p_station: string }
        Returns: Json
      }
      stripe_event_fail: {
        Args: { p_error: string; p_event_id: string; p_type: string }
        Returns: undefined
      }
      subscription_set_customer: {
        Args: { p_customer: string; p_station: string }
        Returns: Json
      }
      subscription_sync: {
        Args: {
          p_customer?: string
          p_event?: string
          p_event_id?: string
          p_period_end?: string
          p_plan?: string
          p_reference?: string
          p_station?: string
          p_status?: Database["public"]["Enums"]["subscription_status"]
          p_subscription?: string
        }
        Returns: Json
      }
      super_admin_create_station: {
        Args: { p_name: string; p_timezone?: string }
        Returns: Json
      }
      super_admin_set_station_suspended: {
        Args: { p_reason: string; p_station: string; p_suspended: boolean }
        Returns: Json
      }
      super_admin_stations: {
        Args: never
        Returns: {
          active_admins: number
          active_members: number
          created_at: string
          last_published_at: string
          last_published_month: number
          last_published_year: number
          name: string
          pending_invites: number
          slug: string
          station_id: string
          status: Database["public"]["Enums"]["subscription_status"]
          suspended_at: string
          timezone: string
          trial_ends_at: string
          writable: boolean
        }[]
      }
      super_admin_support_schedules: {
        Args: { p_reason: string; p_station: string }
        Returns: Json
      }
      unite_weekend: { Args: { p_date: string }; Returns: string }
    }
    Enums: {
      assignment_status:
        | "proposed"
        | "accepted"
        | "declined"
        | "replaced"
        | "cancelled"
      availability_status: "available" | "absent"
      membership_role: "member" | "admin"
      membership_status: "invited" | "active" | "disabled"
      notification_channel: "push" | "email" | "inapp"
      notification_type:
        | "invitation"
        | "availability_reminder"
        | "assignment_proposed"
        | "assignment_reminder"
        | "assignment_declined"
        | "assignment_changed"
        | "assignment_cancelled"
        | "schedule_validated"
        | "schedule_all_accepted"
        | "late_responders"
        | "subscription_trial_ending"
        | "subscription_suspended"
      period_status: "open" | "locked"
      push_platform: "ios" | "android" | "web"
      schedule_status: "draft" | "published" | "validated" | "archived"
      slot_type: "day" | "night"
      subscription_status:
        | "trialing"
        | "active"
        | "past_due"
        | "suspended"
        | "cancelled"
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      assignment_status: [
        "proposed",
        "accepted",
        "declined",
        "replaced",
        "cancelled",
      ],
      availability_status: ["available", "absent"],
      membership_role: ["member", "admin"],
      membership_status: ["invited", "active", "disabled"],
      notification_channel: ["push", "email", "inapp"],
      notification_type: [
        "invitation",
        "availability_reminder",
        "assignment_proposed",
        "assignment_reminder",
        "assignment_declined",
        "assignment_changed",
        "assignment_cancelled",
        "schedule_validated",
        "schedule_all_accepted",
        "late_responders",
        "subscription_trial_ending",
        "subscription_suspended",
      ],
      period_status: ["open", "locked"],
      push_platform: ["ios", "android", "web"],
      schedule_status: ["draft", "published", "validated", "archived"],
      slot_type: ["day", "night"],
      subscription_status: [
        "trialing",
        "active",
        "past_due",
        "suspended",
        "cancelled",
      ],
    },
  },
} as const

