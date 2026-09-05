export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
	// Allows to automatically instantiate createClient with right options
	// instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
	__InternalSupabase: {
		PostgrestVersion: '14.5';
	};
	community_orgs: {
		Tables: {
			accreditation: {
				Row: {
					accreditation_id: string;
					certification_type: string | null;
					inserted_at: string | null;
					inserted_by: string | null;
					issuing_body: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string | null;
					valid_from: string | null;
					valid_until: string | null;
				};
				Insert: {
					accreditation_id?: string;
					certification_type?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					issuing_body?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					valid_from?: string | null;
					valid_until?: string | null;
				};
				Update: {
					accreditation_id?: string;
					certification_type?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					issuing_body?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					valid_from?: string | null;
					valid_until?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'accreditation_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			aliases: {
				Row: {
					alias: string | null;
					alias_id: string;
					alias_type: Database['community_orgs']['Enums']['alias_type_enum'] | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string | null;
				};
				Insert: {
					alias?: string | null;
					alias_id?: string;
					alias_type?: Database['community_orgs']['Enums']['alias_type_enum'] | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
				};
				Update: {
					alias?: string | null;
					alias_id?: string;
					alias_type?: Database['community_orgs']['Enums']['alias_type_enum'] | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'aliases_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			contact_info: {
				Row: {
					contact_id: string;
					email: string | null;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string | null;
					phone: Json | null;
					physical_address: string | null;
					postal_address: string | null;
					social_media: Json | null;
					website: string | null;
				};
				Insert: {
					contact_id?: string;
					email?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					phone?: Json | null;
					physical_address?: string | null;
					postal_address?: string | null;
					social_media?: Json | null;
					website?: string | null;
				};
				Update: {
					contact_id?: string;
					email?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					phone?: Json | null;
					physical_address?: string | null;
					postal_address?: string | null;
					social_media?: Json | null;
					website?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'contact_info_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			dgr_endorsement: {
				Row: {
					dgr_funds: string | null;
					dgr_items: string | null;
					endorsement_end_date: string | null;
					endorsement_id: string;
					endorsement_start_date: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					legal_id: string | null;
				};
				Insert: {
					dgr_funds?: string | null;
					dgr_items?: string | null;
					endorsement_end_date?: string | null;
					endorsement_id?: string;
					endorsement_start_date?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					legal_id?: string | null;
				};
				Update: {
					dgr_funds?: string | null;
					dgr_items?: string | null;
					endorsement_end_date?: string | null;
					endorsement_id?: string;
					endorsement_start_date?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					legal_id?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'dgr_endorsement_legal_id_fkey';
						columns: ['legal_id'];
						isOneToOne: true;
						referencedRelation: 'legal_details';
						referencedColumns: ['legal_id'];
					}
				];
			};
			documents: {
				Row: {
					category: string;
					document_id: string;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					name: string;
					org_id: string | null;
					url: string;
				};
				Insert: {
					category?: string;
					document_id?: string;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					name: string;
					org_id?: string | null;
					url: string;
				};
				Update: {
					category?: string;
					document_id?: string;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					name?: string;
					org_id?: string | null;
					url?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'documents_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			financial_info: {
				Row: {
					annual_budget: number | null;
					auditor_details: Json | null;
					finance_id: string;
					financial_year_end: string | null;
					funding_sources: string[] | null;
					inserted_at: string | null;
					inserted_by: string | null;
					last_audit_date: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string | null;
				};
				Insert: {
					annual_budget?: number | null;
					auditor_details?: Json | null;
					finance_id?: string;
					financial_year_end?: string | null;
					funding_sources?: string[] | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_audit_date?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
				};
				Update: {
					annual_budget?: number | null;
					auditor_details?: Json | null;
					finance_id?: string;
					financial_year_end?: string | null;
					funding_sources?: string[] | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_audit_date?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'financial_info_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			governance: {
				Row: {
					board_structure: Json | null;
					constitution: string | null;
					governance_id: string;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_chart: string | null;
					org_id: string | null;
				};
				Insert: {
					board_structure?: Json | null;
					constitution?: string | null;
					governance_id?: string;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_chart?: string | null;
					org_id?: string | null;
				};
				Update: {
					board_structure?: Json | null;
					constitution?: string | null;
					governance_id?: string;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_chart?: string | null;
					org_id?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'governance_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			historical_info: {
				Row: {
					founding_members: string[] | null;
					history_id: string;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					milestone_date: string | null;
					milestone_description: string | null;
					org_id: string | null;
					structural_changes: Json | null;
				};
				Insert: {
					founding_members?: string[] | null;
					history_id?: string;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					milestone_date?: string | null;
					milestone_description?: string | null;
					org_id?: string | null;
					structural_changes?: Json | null;
				};
				Update: {
					founding_members?: string[] | null;
					history_id?: string;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					milestone_date?: string | null;
					milestone_description?: string | null;
					org_id?: string | null;
					structural_changes?: Json | null;
				};
				Relationships: [
					{
						foreignKeyName: 'historical_info_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			legal_details: {
				Row: {
					abn: string | null;
					abn_activated: string | null;
					abn_last_updated: string | null;
					abn_status: boolean | null;
					acn: string | null;
					acnc_registered: boolean | null;
					acnc_registered_date: string | null;
					acnc_status: boolean | null;
					charity_type: string | null;
					dgr_endorsement: boolean | null;
					entity_type: string | null;
					gst_concession_endorsement_date: string | null;
					incorporation_number: string | null;
					incorporation_registration_date: string | null;
					incorporation_status: boolean | null;
					inserted_at: string | null;
					inserted_by: string | null;
					insurance_details: Json | null;
					last_annual_return_date: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					legal_id: string;
					org_id: string | null;
					tax_concession_endorsement: string | null;
				};
				Insert: {
					abn?: string | null;
					abn_activated?: string | null;
					abn_last_updated?: string | null;
					abn_status?: boolean | null;
					acn?: string | null;
					acnc_registered?: boolean | null;
					acnc_registered_date?: string | null;
					acnc_status?: boolean | null;
					charity_type?: string | null;
					dgr_endorsement?: boolean | null;
					entity_type?: string | null;
					gst_concession_endorsement_date?: string | null;
					incorporation_number?: string | null;
					incorporation_registration_date?: string | null;
					incorporation_status?: boolean | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					insurance_details?: Json | null;
					last_annual_return_date?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					legal_id?: string;
					org_id?: string | null;
					tax_concession_endorsement?: string | null;
				};
				Update: {
					abn?: string | null;
					abn_activated?: string | null;
					abn_last_updated?: string | null;
					abn_status?: boolean | null;
					acn?: string | null;
					acnc_registered?: boolean | null;
					acnc_registered_date?: string | null;
					acnc_status?: boolean | null;
					charity_type?: string | null;
					dgr_endorsement?: boolean | null;
					entity_type?: string | null;
					gst_concession_endorsement_date?: string | null;
					incorporation_number?: string | null;
					incorporation_registration_date?: string | null;
					incorporation_status?: boolean | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					insurance_details?: Json | null;
					last_annual_return_date?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					legal_id?: string;
					org_id?: string | null;
					tax_concession_endorsement?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'legal_details_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			locations: {
				Row: {
					address: string | null;
					geom: unknown;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					latitude: number | null;
					location_id: string;
					location_type: string | null;
					longitude: number | null;
					name: string;
					org_id: string | null;
				};
				Insert: {
					address?: string | null;
					geom?: unknown;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					latitude?: number | null;
					location_id?: string;
					location_type?: string | null;
					longitude?: number | null;
					name: string;
					org_id?: string | null;
				};
				Update: {
					address?: string | null;
					geom?: unknown;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					latitude?: number | null;
					location_id?: string;
					location_type?: string | null;
					longitude?: number | null;
					name?: string;
					org_id?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'locations_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			operational_details: {
				Row: {
					accessibility_features: string[] | null;
					inserted_at: string | null;
					inserted_by: string | null;
					languages_supported: string[] | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					op_id: string;
					operating_hours: Json | null;
					org_id: string | null;
					service_area: string | null;
					staff_count_paid: number | null;
					staff_count_volunteer: number | null;
					target_demographics: string | null;
				};
				Insert: {
					accessibility_features?: string[] | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					languages_supported?: string[] | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					op_id?: string;
					operating_hours?: Json | null;
					org_id?: string | null;
					service_area?: string | null;
					staff_count_paid?: number | null;
					staff_count_volunteer?: number | null;
					target_demographics?: string | null;
				};
				Update: {
					accessibility_features?: string[] | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					languages_supported?: string[] | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					op_id?: string;
					operating_hours?: Json | null;
					org_id?: string | null;
					service_area?: string | null;
					staff_count_paid?: number | null;
					staff_count_volunteer?: number | null;
					target_demographics?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'operational_details_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			org_members: {
				Row: {
					created_at: string | null;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					member_id: string;
					org_id: string | null;
					role: string | null;
					user_id: string | null;
				};
				Insert: {
					created_at?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					member_id?: string;
					org_id?: string | null;
					role?: string | null;
					user_id?: string | null;
				};
				Update: {
					created_at?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					member_id?: string;
					org_id?: string | null;
					role?: string | null;
					user_id?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'org_members_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			org_visibility: {
				Row: {
					allowed_org_ids: number[] | null;
					created_at: string | null;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string | null;
					visibility_id: string;
					visibility_type: string | null;
				};
				Insert: {
					allowed_org_ids?: number[] | null;
					created_at?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					visibility_id?: string;
					visibility_type?: string | null;
				};
				Update: {
					allowed_org_ids?: number[] | null;
					created_at?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					visibility_id?: string;
					visibility_type?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'org_visibility_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			organisations: {
				Row: {
					created_at: string | null;
					date_established: string | null;
					description: string | null;
					entity_name: string;
					inserted_at: string | null;
					inserted_by: string | null;
					is_public: boolean;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string;
					slug: string;
				};
				Insert: {
					created_at?: string | null;
					date_established?: string | null;
					description?: string | null;
					entity_name: string;
					inserted_at?: string | null;
					inserted_by?: string | null;
					is_public?: boolean;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string;
					slug: string;
				};
				Update: {
					created_at?: string | null;
					date_established?: string | null;
					description?: string | null;
					entity_name?: string;
					inserted_at?: string | null;
					inserted_by?: string | null;
					is_public?: boolean;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string;
					slug?: string;
				};
				Relationships: [];
			};
			performance_metrics: {
				Row: {
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					measurement_date: string | null;
					metric_id: string;
					metric_type: string | null;
					metric_value: Json | null;
					org_id: string | null;
					reporting_period: string | null;
				};
				Insert: {
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					measurement_date?: string | null;
					metric_id?: string;
					metric_type?: string | null;
					metric_value?: Json | null;
					org_id?: string | null;
					reporting_period?: string | null;
				};
				Update: {
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					measurement_date?: string | null;
					metric_id?: string;
					metric_type?: string | null;
					metric_value?: Json | null;
					org_id?: string | null;
					reporting_period?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'performance_metrics_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			programs_services: {
				Row: {
					delivery_location: string[] | null;
					description: string | null;
					fee_structure: Json | null;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string | null;
					program_id: string;
					program_name: string | null;
				};
				Insert: {
					delivery_location?: string[] | null;
					description?: string | null;
					fee_structure?: Json | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					program_id?: string;
					program_name?: string | null;
				};
				Update: {
					delivery_location?: string[] | null;
					description?: string | null;
					fee_structure?: Json | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					program_id?: string;
					program_name?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'programs_services_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			relationships: {
				Row: {
					end_date: string | null;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string | null;
					partner_org: string | null;
					relationship_id: string;
					relationship_type: string | null;
					start_date: string | null;
				};
				Insert: {
					end_date?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					partner_org?: string | null;
					relationship_id?: string;
					relationship_type?: string | null;
					start_date?: string | null;
				};
				Update: {
					end_date?: string | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
					partner_org?: string | null;
					relationship_id?: string;
					relationship_type?: string | null;
					start_date?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'relationships_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			reserved_slugs: {
				Row: {
					slug: string;
				};
				Insert: {
					slug: string;
				};
				Update: {
					slug?: string;
				};
				Relationships: [];
			};
			resources_assets: {
				Row: {
					acquisition_date: string | null;
					asset_description: string | null;
					asset_id: string;
					asset_type: string | null;
					asset_value: number | null;
					inserted_at: string | null;
					inserted_by: string | null;
					last_edited_at: string | null;
					last_edited_by: string | null;
					org_id: string | null;
				};
				Insert: {
					acquisition_date?: string | null;
					asset_description?: string | null;
					asset_id?: string;
					asset_type?: string | null;
					asset_value?: number | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
				};
				Update: {
					acquisition_date?: string | null;
					asset_description?: string | null;
					asset_id?: string;
					asset_type?: string | null;
					asset_value?: number | null;
					inserted_at?: string | null;
					inserted_by?: string | null;
					last_edited_at?: string | null;
					last_edited_by?: string | null;
					org_id?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'resources_assets_org_id_fkey';
						columns: ['org_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					}
				];
			};
			role_audit_log: {
				Row: {
					action: string;
					created_at: string | null;
					id: string;
					organisation_id: string;
					performed_by: string | null;
					reason: string | null;
					role_id: string;
					user_id: string;
				};
				Insert: {
					action: string;
					created_at?: string | null;
					id?: string;
					organisation_id: string;
					performed_by?: string | null;
					reason?: string | null;
					role_id: string;
					user_id: string;
				};
				Update: {
					action?: string;
					created_at?: string | null;
					id?: string;
					organisation_id?: string;
					performed_by?: string | null;
					reason?: string | null;
					role_id?: string;
					user_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'role_audit_log_organisation_id_fkey';
						columns: ['organisation_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					},
					{
						foreignKeyName: 'role_audit_log_role_id_fkey';
						columns: ['role_id'];
						isOneToOne: false;
						referencedRelation: 'roles';
						referencedColumns: ['id'];
					}
				];
			};
			role_requests: {
				Row: {
					created_at: string | null;
					id: string;
					message: string | null;
					organisation_id: string;
					reviewed_at: string | null;
					reviewed_by: string | null;
					role_id: string;
					status: string | null;
					updated_at: string | null;
					user_id: string;
				};
				Insert: {
					created_at?: string | null;
					id?: string;
					message?: string | null;
					organisation_id: string;
					reviewed_at?: string | null;
					reviewed_by?: string | null;
					role_id: string;
					status?: string | null;
					updated_at?: string | null;
					user_id: string;
				};
				Update: {
					created_at?: string | null;
					id?: string;
					message?: string | null;
					organisation_id?: string;
					reviewed_at?: string | null;
					reviewed_by?: string | null;
					role_id?: string;
					status?: string | null;
					updated_at?: string | null;
					user_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'role_requests_organisation_id_fkey';
						columns: ['organisation_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					},
					{
						foreignKeyName: 'role_requests_role_id_fkey';
						columns: ['role_id'];
						isOneToOne: false;
						referencedRelation: 'roles';
						referencedColumns: ['id'];
					}
				];
			};
			roles: {
				Row: {
					created_at: string | null;
					description: string | null;
					hierarchy_level: number | null;
					id: string;
					is_system_role: boolean | null;
					name: string;
					permissions: Json | null;
				};
				Insert: {
					created_at?: string | null;
					description?: string | null;
					hierarchy_level?: number | null;
					id?: string;
					is_system_role?: boolean | null;
					name: string;
					permissions?: Json | null;
				};
				Update: {
					created_at?: string | null;
					description?: string | null;
					hierarchy_level?: number | null;
					id?: string;
					is_system_role?: boolean | null;
					name?: string;
					permissions?: Json | null;
				};
				Relationships: [];
			};
			user_organisation_roles: {
				Row: {
					created_at: string | null;
					expires_at: string | null;
					granted_at: string | null;
					granted_by: string | null;
					id: string;
					is_active: boolean | null;
					organisation_id: string;
					role_id: string;
					updated_at: string | null;
					user_id: string;
				};
				Insert: {
					created_at?: string | null;
					expires_at?: string | null;
					granted_at?: string | null;
					granted_by?: string | null;
					id?: string;
					is_active?: boolean | null;
					organisation_id: string;
					role_id: string;
					updated_at?: string | null;
					user_id: string;
				};
				Update: {
					created_at?: string | null;
					expires_at?: string | null;
					granted_at?: string | null;
					granted_by?: string | null;
					id?: string;
					is_active?: boolean | null;
					organisation_id?: string;
					role_id?: string;
					updated_at?: string | null;
					user_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'user_organisation_roles_organisation_id_fkey';
						columns: ['organisation_id'];
						isOneToOne: false;
						referencedRelation: 'organisations';
						referencedColumns: ['org_id'];
					},
					{
						foreignKeyName: 'user_organisation_roles_role_id_fkey';
						columns: ['role_id'];
						isOneToOne: false;
						referencedRelation: 'roles';
						referencedColumns: ['id'];
					}
				];
			};
		};
		Views: {
			[_ in never]: never;
		};
		Functions: {
			expire_roles: { Args: never; Returns: number };
			generate_unique_slug: { Args: { base_slug: string }; Returns: string };
			get_user_all_roles: {
				Args: { p_user_id: string };
				Returns: {
					expires_at: string;
					granted_at: string;
					hierarchy_level: number;
					organisation_id: string;
					organisation_name: string;
					permissions: Json;
					role_id: string;
					role_name: string;
				}[];
			};
			get_user_organisations_with_roles: {
				Args: { p_user_id: string };
				Returns: {
					max_hierarchy_level: number;
					organisation_id: string;
					organisation_name: string;
					organisation_slug: string;
					permissions: Json;
					role_names: string[];
				}[];
			};
			grant_user_role: {
				Args: {
					p_expires_at?: string;
					p_granted_by: string;
					p_organisation_id: string;
					p_role_id: string;
					p_user_id: string;
				};
				Returns: string;
			};
			process_role_request: {
				Args: {
					p_expires_at?: string;
					p_request_id: string;
					p_reviewer_id: string;
					p_status: string;
				};
				Returns: boolean;
			};
			request_role: {
				Args: {
					p_message?: string;
					p_organisation_id: string;
					p_role_id: string;
					p_user_id: string;
				};
				Returns: string;
			};
			revoke_user_role: {
				Args: {
					p_organisation_id: string;
					p_reason?: string;
					p_revoked_by: string;
					p_role_id: string;
					p_user_id: string;
				};
				Returns: boolean;
			};
			user_has_inherited_permission: {
				Args: {
					p_organisation_id: string;
					p_permission: string;
					p_user_id: string;
				};
				Returns: boolean;
			};
			user_has_permission: {
				Args: {
					p_organisation_id: string;
					p_permission: string;
					p_user_id: string;
				};
				Returns: boolean;
			};
			user_max_role_level: {
				Args: { p_organisation_id: string; p_user_id: string };
				Returns: number;
			};
		};
		Enums: {
			alias_type_enum: 'Business Name' | 'Trading Name';
		};
		CompositeTypes: {
			[_ in never]: never;
		};
	};
};

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>];

export type Tables<
	DefaultSchemaTableNameOrOptions extends
		| keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
		| { schema: keyof DatabaseWithoutInternals },
	TableName extends DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
				DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
		: never = never
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
			DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
			Row: infer R;
		}
		? R
		: never
	: DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
		? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
				Row: infer R;
			}
			? R
			: never
		: never;

export type TablesInsert<
	DefaultSchemaTableNameOrOptions extends
		| keyof DefaultSchema['Tables']
		| { schema: keyof DatabaseWithoutInternals },
	TableName extends DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
		: never = never
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
			Insert: infer I;
		}
		? I
		: never
	: DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
		? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
				Insert: infer I;
			}
			? I
			: never
		: never;

export type TablesUpdate<
	DefaultSchemaTableNameOrOptions extends
		| keyof DefaultSchema['Tables']
		| { schema: keyof DatabaseWithoutInternals },
	TableName extends DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
		: never = never
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
			Update: infer U;
		}
		? U
		: never
	: DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
		? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
				Update: infer U;
			}
			? U
			: never
		: never;

export type Enums<
	DefaultSchemaEnumNameOrOptions extends
		| keyof DefaultSchema['Enums']
		| { schema: keyof DatabaseWithoutInternals },
	EnumName extends DefaultSchemaEnumNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
		: never = never
> = DefaultSchemaEnumNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
	: DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
		? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
		: never;

export type CompositeTypes<
	PublicCompositeTypeNameOrOptions extends
		| keyof DefaultSchema['CompositeTypes']
		| { schema: keyof DatabaseWithoutInternals },
	CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
		: never = never
> = PublicCompositeTypeNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
	: PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
		? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
		: never;

export const Constants = {
	community_orgs: {
		Enums: {
			alias_type_enum: ['Business Name', 'Trading Name']
		}
	}
} as const;
