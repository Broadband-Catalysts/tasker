setup_tasker_db             package:tasker             R Documentation

_I_n_i_t_i_a_l_i_z_e _t_a_s_k_e_r _D_a_t_a_b_a_s_e _S_c_h_e_m_a

_D_e_s_c_r_i_p_t_i_o_n:

     Creates the necessary PostgreSQL schema and tables for tasker.
     This function should be run once to set up the database.

_U_s_a_g_e:

     setup_tasker_db(
       conn = NULL,
       schema_name = "tasker",
       force = FALSE,
       skip_backup = FALSE
     )
     
_A_r_g_u_m_e_n_t_s:

    conn: Optional database connection. If NULL, uses connection from
          config.

schema_name: Name of the schema to create (default: "tasker")

   force: If TRUE, recreates schema while preserving existing data via
          backup

skip_backup: If TRUE, skips data backup (USE WITH CAUTION)

_D_e_t_a_i_l_s:

     SAFETY FEATURES:

        • Uses transactions to rollback on failure

        • Preserves existing data by backing up to schema_backup

        • Only drops backup after successful migration

_V_a_l_u_e:

     TRUE if successful

_E_x_a_m_p_l_e_s:

     ## Not run:
     
     # Initialize with default config
     setup_tasker_db()
     
     # Initialize with specific connection
     conn <- DBI::dbConnect(RPostgres::Postgres(), ...)
     setup_tasker_db(conn)
     
     # Force recreate (backs up existing data first!)
     setup_tasker_db(force = TRUE)
     ## End(Not run)
     

