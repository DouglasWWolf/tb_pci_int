# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CLK_PER_MSEC" -parent ${Page_0}


}

proc update_PARAM_VALUE.CLK_PER_MSEC { PARAM_VALUE.CLK_PER_MSEC } {
	# Procedure called to update CLK_PER_MSEC when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_PER_MSEC { PARAM_VALUE.CLK_PER_MSEC } {
	# Procedure called to validate CLK_PER_MSEC
	return true
}


proc update_MODELPARAM_VALUE.CLK_PER_MSEC { MODELPARAM_VALUE.CLK_PER_MSEC PARAM_VALUE.CLK_PER_MSEC } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_PER_MSEC}] ${MODELPARAM_VALUE.CLK_PER_MSEC}
}

