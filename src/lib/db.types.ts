export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  community_orgs: {
    Tables: {
      accreditation: {
        Row: {
          accred_id: number
          certification_type: string | null
          inserted_at: string | null
          inserted_by: string | null
          issuing_body: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          org_id: number | null
          valid_from: string | null
          valid_until: string | null
        }
        Insert: {
          accred_id?: number
          certification_type?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          issuing_body?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
          valid_from?: string | null
          valid_until?: string | null
        }
        Update: {
          accred_id?: number
          certification_type?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          issuing_body?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
          valid_from?: string | null
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "accreditation_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      contact_info: {
        Row: {
          contact_id: number
          email: string | null
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          org_id: number | null
          phone: string | null
          physical_address: string | null
          postal_address: string | null
          social_media: Json | null
          website: string | null
        }
        Insert: {
          contact_id?: number
          email?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
          phone?: string | null
          physical_address?: string | null
          postal_address?: string | null
          social_media?: Json | null
          website?: string | null
        }
        Update: {
          contact_id?: number
          email?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
          phone?: string | null
          physical_address?: string | null
          postal_address?: string | null
          social_media?: Json | null
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contact_info_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      financial_info: {
        Row: {
          annual_budget: number | null
          auditor_details: Json | null
          finance_id: number
          financial_year_end: string | null
          funding_sources: string[] | null
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          org_id: number | null
        }
        Insert: {
          annual_budget?: number | null
          auditor_details?: Json | null
          finance_id?: number
          financial_year_end?: string | null
          funding_sources?: string[] | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
        }
        Update: {
          annual_budget?: number | null
          auditor_details?: Json | null
          finance_id?: number
          financial_year_end?: string | null
          funding_sources?: string[] | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "financial_info_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      governance: {
        Row: {
          board_structure: Json | null
          constitution: string | null
          governance_id: number
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          org_chart: string | null
          org_id: number | null
        }
        Insert: {
          board_structure?: Json | null
          constitution?: string | null
          governance_id?: number
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_chart?: string | null
          org_id?: number | null
        }
        Update: {
          board_structure?: Json | null
          constitution?: string | null
          governance_id?: number
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_chart?: string | null
          org_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "governance_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      historical_info: {
        Row: {
          founding_members: string[] | null
          history_id: number
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          milestone_date: string | null
          milestone_description: string | null
          org_id: number | null
          structural_changes: Json | null
        }
        Insert: {
          founding_members?: string[] | null
          history_id?: number
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          milestone_date?: string | null
          milestone_description?: string | null
          org_id?: number | null
          structural_changes?: Json | null
        }
        Update: {
          founding_members?: string[] | null
          history_id?: number
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          milestone_date?: string | null
          milestone_description?: string | null
          org_id?: number | null
          structural_changes?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "historical_info_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      legal_details: {
        Row: {
          abn: string | null
          acn: string | null
          acnc_status: boolean | null
          entity_type: string | null
          inserted_at: string | null
          inserted_by: string | null
          insurance_details: Json | null
          last_edited_at: string | null
          last_edited_by: string | null
          legal_id: number
          org_id: number | null
          tax_status: string | null
        }
        Insert: {
          abn?: string | null
          acn?: string | null
          acnc_status?: boolean | null
          entity_type?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          insurance_details?: Json | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          legal_id?: number
          org_id?: number | null
          tax_status?: string | null
        }
        Update: {
          abn?: string | null
          acn?: string | null
          acnc_status?: boolean | null
          entity_type?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          insurance_details?: Json | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          legal_id?: number
          org_id?: number | null
          tax_status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "legal_details_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      operational_details: {
        Row: {
          accessibility_features: string[] | null
          inserted_at: string | null
          inserted_by: string | null
          languages_supported: string[] | null
          last_edited_at: string | null
          last_edited_by: string | null
          op_id: number
          operating_hours: Json | null
          org_id: number | null
          service_area: string | null
          staff_count_paid: number | null
          staff_count_volunteer: number | null
          target_demographics: string | null
        }
        Insert: {
          accessibility_features?: string[] | null
          inserted_at?: string | null
          inserted_by?: string | null
          languages_supported?: string[] | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          op_id?: number
          operating_hours?: Json | null
          org_id?: number | null
          service_area?: string | null
          staff_count_paid?: number | null
          staff_count_volunteer?: number | null
          target_demographics?: string | null
        }
        Update: {
          accessibility_features?: string[] | null
          inserted_at?: string | null
          inserted_by?: string | null
          languages_supported?: string[] | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          op_id?: number
          operating_hours?: Json | null
          org_id?: number | null
          service_area?: string | null
          staff_count_paid?: number | null
          staff_count_volunteer?: number | null
          target_demographics?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "operational_details_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      organisations: {
        Row: {
          created_at: string | null
          date_established: string | null
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          legal_name: string
          org_id: number
          trading_name: string | null
        }
        Insert: {
          created_at?: string | null
          date_established?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          legal_name: string
          org_id?: number
          trading_name?: string | null
        }
        Update: {
          created_at?: string | null
          date_established?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          legal_name?: string
          org_id?: number
          trading_name?: string | null
        }
        Relationships: []
      }
      performance_metrics: {
        Row: {
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          measurement_date: string | null
          metric_id: number
          metric_type: string | null
          metric_value: Json | null
          org_id: number | null
          reporting_period: string | null
        }
        Insert: {
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          measurement_date?: string | null
          metric_id?: number
          metric_type?: string | null
          metric_value?: Json | null
          org_id?: number | null
          reporting_period?: string | null
        }
        Update: {
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          measurement_date?: string | null
          metric_id?: number
          metric_type?: string | null
          metric_value?: Json | null
          org_id?: number | null
          reporting_period?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "performance_metrics_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      programs_services: {
        Row: {
          delivery_location: string[] | null
          description: string | null
          fee_structure: Json | null
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          org_id: number | null
          program_id: number
          program_name: string | null
        }
        Insert: {
          delivery_location?: string[] | null
          description?: string | null
          fee_structure?: Json | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
          program_id?: number
          program_name?: string | null
        }
        Update: {
          delivery_location?: string[] | null
          description?: string | null
          fee_structure?: Json | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
          program_id?: number
          program_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "programs_services_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      relationships: {
        Row: {
          end_date: string | null
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          org_id: number | null
          partner_org: string | null
          relationship_id: number
          relationship_type: string | null
          start_date: string | null
        }
        Insert: {
          end_date?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
          partner_org?: string | null
          relationship_id?: number
          relationship_type?: string | null
          start_date?: string | null
        }
        Update: {
          end_date?: string | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
          partner_org?: string | null
          relationship_id?: number
          relationship_type?: string | null
          start_date?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "relationships_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
      resources_assets: {
        Row: {
          acquisition_date: string | null
          asset_description: string | null
          asset_id: number
          asset_type: string | null
          asset_value: number | null
          inserted_at: string | null
          inserted_by: string | null
          last_edited_at: string | null
          last_edited_by: string | null
          org_id: number | null
        }
        Insert: {
          acquisition_date?: string | null
          asset_description?: string | null
          asset_id?: number
          asset_type?: string | null
          asset_value?: number | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
        }
        Update: {
          acquisition_date?: string | null
          asset_description?: string | null
          asset_id?: number
          asset_type?: string | null
          asset_value?: number | null
          inserted_at?: string | null
          inserted_by?: string | null
          last_edited_at?: string | null
          last_edited_by?: string | null
          org_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "resources_assets_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["org_id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type PublicSchema = Database[Extract<keyof Database, "public">]

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (PublicSchema["Tables"] & PublicSchema["Views"])
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
        Database[PublicTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
      Database[PublicTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (PublicSchema["Tables"] &
        PublicSchema["Views"])
    ? (PublicSchema["Tables"] &
        PublicSchema["Views"])[PublicTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  PublicEnumNameOrOptions extends
    | keyof PublicSchema["Enums"]
    | { schema: keyof Database },
  EnumName extends PublicEnumNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = PublicEnumNameOrOptions extends { schema: keyof Database }
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof PublicSchema["Enums"]
    ? PublicSchema["Enums"][PublicEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof PublicSchema["CompositeTypes"]
    | { schema: keyof Database },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof Database }
  ? Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof PublicSchema["CompositeTypes"]
    ? PublicSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never
