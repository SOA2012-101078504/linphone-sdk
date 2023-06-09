############################################################################
# GenerateSDK.cmake
# Copyright (C) 2010-2020 Belledonne Communications, Grenoble France
#
############################################################################
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
############################################################################
include(LinphoneSdkUtils)

set(LINPHONESDK_UWP_ARCHS "x86, x64" CACHE STRING "UWP architectures to build for: comma-separated list of values in [x86, x64]")


linphone_sdk_convert_comma_separated_list_to_cmake_list("${LINPHONESDK_UWP_ARCHS}" UWP_ARCHS)

#Configuration

if(NOT LINPHONESDK_DESKTOP_ZIP_PATH AND NOT LINPHONESDK_UWP_ZIP_PATH AND NOT LINPHONESDK_WINDOWSSTORE_ZIP_PATH)
	message(FATAL_ERROR "You need to specify at least one of LINPHONESDK_DESKTOP_ZIP_PATH, LINPHONESDK_UWP_ZIP_PATH, or LINPHONESDK_WINDOWSSTORE_ZIP_PATH")
endif()

function(add_command_from_zip zip_path nuget_folder)
	FILE(GLOB ZIP_FILES ${zip_path}/*.zip)
	set(FILE_ITEM "")
	foreach(item ${ZIP_FILES})
		if("${FILE_ITEM}" STREQUAL "")
			set(FILE_ITEM ${item})
		elseif(${item} IS_NEWER_THAN ${FILE_ITEM})
			set(FILE_ITEM ${item})
		endif()
	endforeach(item)
	if(NOT ${FILE_ITEM} STREQUAL "")
		message(STATUS "-  ${FILE_ITEM}")
		set(out_dir "${CMAKE_BINARY_DIR}/WORK/packages/nuget/${nuget_folder}")
		add_custom_command(TARGET unzip PRE_BUILD
			COMMAND ${CMAKE_COMMAND} -E tar xzf ${FILE_ITEM}
			WORKING_DIRECTORY "${out_dir}"
			COMMENT "Unzipping files : ${FILE_ITEM} into ${out_dir}\n"
			VERBATIM)
		
	else()
		message(FATAL_ERROR ".zip files not found in folder : ${zip_path}.")
	endif()
endfunction()

set(LINPHONESDK_OUTPUT_DIR ${CMAKE_BINARY_DIR}/WORK/packages/nuget)
add_custom_target( unzip ALL)
add_custom_command(TARGET unzip PRE_BUILD COMMAND ${CMAKE_COMMAND} -E remove_directory ${LINPHONESDK_OUTPUT_DIR})
add_custom_command(TARGET unzip PRE_BUILD COMMAND ${CMAKE_COMMAND} -E make_directory ${LINPHONESDK_OUTPUT_DIR}/desktop)
add_custom_command(TARGET unzip PRE_BUILD COMMAND ${CMAKE_COMMAND} -E make_directory ${LINPHONESDK_OUTPUT_DIR}/uwp)
add_custom_command(TARGET unzip PRE_BUILD COMMAND ${CMAKE_COMMAND} -E make_directory ${LINPHONESDK_OUTPUT_DIR}/windowsstore)

if(LINPHONESDK_DESKTOP_ZIP_PATH)
	message(STATUS "Retrieve Desktop build")
	add_command_from_zip(${LINPHONESDK_DESKTOP_ZIP_PATH} "desktop")

	set(NUSPEC_WIN32 "<file src=\"$OutputSdkDir$\\desktop\\desktop\\bin\\*.winmd\" target=\"lib\\win\\\" />
			<file src=\"$OutputSdkDir$\\desktop\\desktop\\bin\\**\\*.*\" target=\"lib\\win\\x86\" exclude=\"**\\*.pc;**\\cmake\\**\"/>
			<file src=\"$OutputSdkDir$\\desktop\\desktop\\lib\\**\\*.*\" target=\"lib\\win\\x86\" exclude=\"**\\*.pc;**\\cmake\\**\"/>
			<file src=\"LinphoneSDK.Windows.targets\" target=\"build\\win\" />
			")
	set(NUSPEC_GENERIC "<file src=\"$OutputSdkDir$\\desktop\\desktop\\share\\**\\*\" exclude=\"**\\cmake\\**\" target=\"content\\\" />")
endif()
if(LINPHONESDK_WINDOWSSTORE_ZIP_PATH)
	message(STATUS "Retrieve Windows Store build")
	add_command_from_zip(${LINPHONESDK_WINDOWSSTORE_ZIP_PATH} "windowsstore")

	set(NUSPEC_WINDOWSSTORE "<file src=\"$OutputSdkDir$\\windowsstore\\desktop\\bin\\*.winmd\" target=\"lib\\netcore\\\" />
		<file src=\"$OutputSdkDir$\\windowsstore\\desktop\\bin\\**\\*.*\" target=\"lib\\netcore\\x86\" exclude=\"**\\*.pc;**\\cmake\\**\"/>
		<file src=\"$OutputSdkDir$\\windowsstore\\desktop\\lib\\**\\*.*\" target=\"lib\\netcore\\x86\" exclude=\"**\\*.pc;**\\cmake\\**\"/>
		<file src=\"LinphoneSDK.Windows.targets\" target=\"build\\netcore\" />
		")
	set(NUSPEC_GENERIC "<file src=\"$OutputSdkDir$\\windowsstore\\desktop\\share\\**\\*\" exclude=\"**\\cmake\\**\" target=\"content\\\" />")
endif()
if(LINPHONESDK_UWP_ZIP_PATH)
	message(STATUS "Retrieve UWP build from [${LINPHONESDK_UWP_ARCHS}] archs.")
	add_command_from_zip(${LINPHONESDK_UWP_ZIP_PATH} "uwp")
	set(NUSPEC_UWP "")
	foreach(UWP_ARCH ${UWP_ARCHS})
		set(NUSPEC_UWP "${NUSPEC_UWP} <file src=\"$OutputSdkDir$\\uwp\\uwp-${UWP_ARCH}\\bin\\*.winmd\" target=\"lib\\uap10.0\\\" />
								<file src=\"$OutputSdkDir$\\uwp\\uwp-${UWP_ARCH}\\bin\\**\\*.*\" target=\"lib\\uap10.0\\${UWP_ARCH}\" exclude=\"**\\*.pc;**\\cmake\\**\" />
								<file src=\"$OutputSdkDir$\\uwp\\uwp-${UWP_ARCH}\\lib\\**\\*.*\" target=\"lib\\uap10.0\\${UWP_ARCH}\" exclude=\"**\\*.pc;**\\cmake\\**\" />
								<file src=\"LinphoneSDK.Windows.targets\" target=\"build\\UAP10.0\" />
		")
		set(NUSPEC_GENERIC "<file src=\"$OutputSdkDir$\\uwp\\uwp-${UWP_ARCH}\\share\\**\\*\" exclude=\"**\\cmake\\**\" target=\"content\\\" />")
	endforeach()
endif()


#Configuration files
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/LinphoneSDK.Windows.nuspec.in ${CMAKE_CURRENT_BINARY_DIR}/LinphoneSDK.Windows.nuspec @ONLY)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/_._ ${CMAKE_CURRENT_BINARY_DIR}/_._)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/LinphoneSDK.Windows.targets.in ${CMAKE_CURRENT_BINARY_DIR}/LinphoneSDK.Windows.targets @ONLY)
if(LINPHONESDK_OUTPUT_DIR)
	file(TO_NATIVE_PATH "${LINPHONESDK_OUTPUT_DIR}" WINDOWS_INSTALL_PATH)
else()
	file(TO_NATIVE_PATH "${CMAKE_INSTALL_PREFIX}" WINDOWS_INSTALL_PATH)
endif()

#Nuget binary
find_program(NUGET_PROGRAM nuget.exe)
if(NOT NUGET_PROGRAM)
	file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/nuget.exe DESTINATION ${CMAKE_CURRENT_BINARY_DIR})
	set(NUGET_PROGRAM "nuget.exe")
endif()

add_custom_target(nuget ALL DEPENDS unzip)

#add_custom_command(TARGET nuget PRE_BUILD
#	COMMAND ${CMAKE_COMMAND} -E rm -rRf "${CMAKE_CURRENT_BINARY_DIR}/packages"
#)
	
add_custom_command(TARGET nuget
	COMMAND ${NUGET_PROGRAM} "pack" "LinphoneSDK.Windows.nuspec" "-Properties" "OutputSdkDir=${WINDOWS_INSTALL_PATH}" "-OutputDirectory" "packages"
	WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)
add_custom_command(TARGET nuget
	COMMAND ${CMAKE_COMMAND} "-E" "copy_directory"  "${CMAKE_CURRENT_BINARY_DIR}/packages" "${CMAKE_INSTALL_PREFIX}/packages"
	WORKING_DIRECTORY ${LINPHONESDK_OUTPUT_DIR}
)
# "-OutputDirectory" "${WINDOWS_INSTALL_PATH}"
