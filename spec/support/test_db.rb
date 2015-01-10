class TestDb

  DATABASES = %w{hr arunit}

  def self.build
    db = self.new
    db.drop_databases(DATABASES)
    db.create_databases(DATABASES)
    db.connection.logoff
  end

  def self.database_version
     db = self.new
     db.database_version
  end

  def self.drop
    db = self.new
    db.drop_databases(DATABASES)
    db.connection.logoff
  end

  def connection
    unless defined?(@connection)
      begin
        Timeout::timeout(5) {
          if defined?(JRUBY_VERSION)
            @connection = java.sql.DriverManager.get_connection(
              'jdbc:oracle:thin:@127.0.0.1:1521/XE',
              'system',
              'oracle'
            );
          else
            @connection = OCI8.new(
              'system',
              'oracle',
              '(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=127.0.0.1)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=XE)))'
            )
          end
        }
      rescue Timeout::Error
        raise "Cannot establish connection with Oracle database as SYSTEM user. Seams you need to start local Oracle database"
      end
    end
    @connection
  end

  def drop_databases(databases=[])
    return unless connection
    databases.each do |db|
      execute_statement(<<-STATEMENT
        DECLARE
           v_count INTEGER := 0;
           l_cnt   INTEGER;
        BEGIN

          SELECT COUNT (1)
            INTO v_count
            FROM dba_users
            WHERE username = UPPER('#{db}');

          IF v_count != 0 THEN
            FOR x IN (SELECT *
                        FROM v$session
                        WHERE username = UPPER('#{db}'))
            LOOP
              EXECUTE IMMEDIATE 'alter system kill session ''' || x.sid || ',' || x.serial# || ''' IMMEDIATE';
            END LOOP;

            EXECUTE IMMEDIATE ('DROP USER #{db} CASCADE');
          END IF;
        END;
        STATEMENT
      )
    end
  end

  def create_databases(databases=[])
    return unless connection
    databases.each do |db|
      execute_statement(<<-STATEMENT
        DECLARE
           v_count INTEGER := 0;
        BEGIN

          SELECT COUNT (1)
            INTO v_count
            FROM dba_users
            WHERE username = UPPER ('#{db}');

          IF v_count = 0 THEN
            EXECUTE IMMEDIATE ('CREATE USER #{db} IDENTIFIED BY #{db}');
            EXECUTE IMMEDIATE ('GRANT unlimited tablespace, create session, create table, create sequence, create procedure, create type, create view, create synonym TO #{db}');
            EXECUTE IMMEDIATE ('ALTER USER #{db} QUOTA 50m ON SYSTEM');
          END IF;
        END;
        STATEMENT
      )
    end
  end

  def database_version
    query = 'SELECT version FROM V$INSTANCE'

    if defined?(JRUBY_VERSION)
      statement = connection.create_statement
      resource  = statement.execute_query(query)

      resource.next
      value = resource.get_string('VERSION')

      resource.close
      statement.close
    else
      cursor = execute_statement(query)
      value = cursor.fetch()[0]
      cursor.close
    end

    value.match(/(.*)\.\d$/)[1]
  end

  def execute_statement(statement)
    if defined?(JRUBY_VERSION)
      statement = connection.prepare_call(statement)
      statement.execute
      statement.close
    else
      connection.exec(statement)
    end
  end
end
