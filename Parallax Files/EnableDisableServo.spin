{{
*****************************************
* EnableDisableServo        v1.0        *
* Author: Beau Schwabe                  *
* Copyright (c) 2009 Parallax           *
* See end of file for terms of use.     *
*****************************************

 History:
          Version 1 - (05-15-2008) initial concept

}}
CON
_clkmode          = xtal1 + pll16x                      
_xinfreq          = 5_000_000

''                              Pin Definitions
USB_Rx            = 31
USB_Tx            = 30
I2C_Data          = 29
I2C_Clock         = 28
Serial_Rx_Tx      = 27
SerialActivityPin = 26
Control           = 25
NotUsed_8         = 24
NotUsed_7         = 23
NotUsed_6         = 22
NotUsed_5         = 21
NotUsed_4         = 20
NotUsed_3         = 19
NotUsed_2         = 18
NotUsed_1         = 17
NotUsed_0         = 16
Servo_15          = 15
Servo_14          = 14
Servo_13          = 13
Servo_12          = 12
Servo_11          = 11
Servo_10          = 10
Servo_9           = 9
Servo_8           = 8
Servo_7           = 7
Servo_6           = 6
Servo_5           = 5
Servo_4           = 4
Servo_3           = 3
Servo_2           = 2
Servo_1           = 1
Servo_0           = 0

{{
             EEPROM:
          ┌───────────┐ 
          │    32K    │$0000
          │           │         
          │ Propeller │
          │  Program  │
          │           │$7FFF
          ├───────────┤
          │    32K    │$8000
          │           │
          │ User Data │
          │           │
          │           │$FFFF
          └───────────┘
}}

SoftwareSwitch  = $8000             ' Memory position to hold software Switch

                                    ' Bit 0 holds the port value ; 0 - Servos 0 to 15 ; 1 - Servos 16 to 31
                                    ' Bit 1 indicates if servo startup values other than the default 1500us are used 

EnabledIOs      = $8001 'highbyte   ' Memory position to hold servo's that are
'                 $8002 'lowbyte    ' Enabled or Disabled upon Startup
                                    ' Only bits 0 to 15 are used

ServoCh0        = $8003 'highbyte   ' locations $8003 to $8022 Hold Optional servo startup values
'                 $8004 'lowbyte
ServoCh1        = $8005 'highbyte
'                 $8006 'lowbyte
ServoCh2        = $8007 'highbyte
'                 $8008 'lowbyte
ServoCh3        = $8009 'highbyte
'                 $800A 'lowbyte
ServoCh4        = $800B 'highbyte
'                 $800C 'lowbyte
ServoCh5        = $800D 'highbyte
'                 $800E 'lowbyte
ServoCh6        = $800F 'highbyte
'                 $8010 'lowbyte
ServoCh7        = $8011 'highbyte
'                 $8012 'lowbyte
ServoCh8        = $8013 'highbyte
'                 $8014 'lowbyte
ServoCh9        = $8015 'highbyte
'                 $8016 'lowbyte
ServoCh10       = $8017 'highbyte
'                 $8018 'lowbyte
ServoCh11       = $8019 'highbyte
'                 $801A 'lowbyte
ServoCh12       = $801B 'highbyte
'                 $801C 'lowbyte
ServoCh13       = $801D 'highbyte
'                 $801E 'lowbyte
ServoCh14       = $801F 'highbyte
'                 $8020 'lowbyte
ServoCh15       = $8021 'highbyte
'                 $8022 'lowbyte


EEPR0M          = $FFFA             ' Reserved for initial EEPROM programming 
'                 $FFFB
'                 $FFFC
'                 $FFFD
'                 $FFFE
'                 $FFFF                                                    

OBJ
  SERVO         :          "Servo32v7.spin"
  EEPROM        :     "Very Basic I2C.spin"  
  COMport1      :   "FullDuplexSerial.spin"
  COMport2      :   "FullDuplexSerial.spin"

VAR
long    Stack[30]                                       ' for Serial activity indicator cog

long    Enabled                                         ' Servo Enabled or Disabled
long    temp
long    Speed

word    Baud
byte    Rx, U_Flag         

byte    PortMode                                        ' port select
byte    BaudMode                                        ' baud speed data
byte    PortDetect
byte    LoadDetect

byte    Channel                                         ' active channel 
byte    Ramp                                            ' Servo Delay time
byte    PortRequest   
byte    ServoRamp[16]                                   ' Servo Ramp value
   
word    ServoPosition[16]                               ' Location of Servo.

                                                        ' Note:  This is used only within the PSC,
                                                        '        to read back the the Current Servo
                                                        '        position.  The servo32 object keeps
                                                        '        track of all 32 servos seperately
                                                        '        within that object. 

PUB  EnableDisableServo|Edata,Tdata

''Initialize -----------------------------------------------------------------------

     Baud  := 2400
     Baudmode := 0
     Speed := 0       

     EEPROM.Initialize                                  '' Initialize EEPROM

'----------------------------------------------------------------------------------
'     PW := %00000000_00000001
'     EEPROM.ByteWrite(EnabledIOs+0,PW_highbyte)         '' Find which servo's are enabled                             
'     EEPROM.ByteWrite(EnabledIOs+1,PW_lowbyte)
'----------------------------------------------------------------------------------      

     CheckUpperEEPROM                                   '' Check if EEPROM has ever been initialized
                                                        '' and if not set EEPROM to default settings.

     PortDetect  := EEPROM.RandomRead(SoftwareSwitch) & %1          '' Get Port Number            
     LoadDetect  := (EEPROM.RandomRead(SoftwareSwitch) & %10)>>1    '' Determine default or preset 
                                                                    '' servo positions to use
                                                                    
     PW_highbyte := EEPROM.RandomRead(EnabledIOs+0)     '' Find which servo's are enabled                             
     PW_lowbyte  := EEPROM.RandomRead(EnabledIOs+1)
     Enabled := PW




                                                        '' Monitor Serial activity
     Cognew(SerialIndicator(USB_Rx,USB_Tx,Serial_Rx_Tx,SerialActivityPin),@Stack)
     
     
     if ina[USB_Rx] == 0        '' Check to see if USB port is powered
        outa[USB_Tx] := 0       '' Force Propeller Tx line LOW if USB not connected
     else
        COMport1.start(USB_Rx, USB_Tx, 0, Baud)             '' Initialize serial communication to the PC
     
     COMport2.start(Serial_Rx_Tx, Serial_Rx_Tx, %0100, Baud)'' Initialize serial communication to the Serial Plug

     SERVO.Start                                        '' Start Servo Handler
     SERVO.Ramp                                         '' Start Background Ramping

''Initialize Loop ------------------------------------------------------------------

     repeat temp from 0 to 15   '' Initialize ALL servos to center position that are Enabled on Startup
       If ((Enabled & |<temp)>>temp) == 0               '' Check if servo is enabled on startup
          PW := 750                                     '' Set default Servo Width value
          If LoadDetect == 1                            '' Check if pre-defined Servo position has been selected
             PW_highbyte := EEPROM.RandomRead(ServoCh0+(temp<<1)+0)             '' Load pre-defined HIGH BYTE
             PW_lowbyte  := EEPROM.RandomRead(ServoCh0+(temp<<1)+1)             '' Load pre-defined LOW BYTE
             if PW < 250 or PW > 1250                   '' Check if pre-defined Servo position is within valid range 
                PW := 750                               '' ...If not default to center position
          Servo.Set(temp,PW<<1)                         '' Initialize servo position                    

''MainLoop -------------------------------------------------------------------------
     U_Flag := 0
     repeat
       Rx := GetDataByte
      case Rx                                             '' Continue with PSC command Parsing
         0..31 :
                 if GetDataByte == 13 
                 Channel := Rx
                 Channel := 0#>Channel<#31 
                 PortRequest := (Channel & %10000)>>4
                 If PortDetect == PortRequest
                       Channel &= %01111 
                       ToggleServo
         "F":
            Rx := GetDataByte
            Channel := Rx
            Channel := 0#>Channel<#31
            PortRequest := (Channel & %10000)>>4
            If PortDetect == PortRequest
               Channel &= %01111
               GoCCW
         "B":
            Rx := GetDataByte
            Channel := Rx
            Channel := 0#>Channel<#31
            PortRequest := (Channel & %10000)>>4
            If PortDetect == PortRequest
               Channel &= %01111
                GoCW    
         "U":
            IncreaseSpeed
         "D":
            DecreaseSpeed
         "Z":
            ZeroSpeed
         "S":
                 Rx := GetDataByte
                 Channel := Rx
                 Channel := 0#>Channel<#31
                 PortRequest := (Channel & %10000)>>4
                 If PortDetect == PortRequest
                       Channel &= %01111
                       GoStop 
         "P"   : Rx := GetDataByte
                 if Rx == "S"
                    Rx := GetDataByte
                    if Rx == "S"
                       PortMode := GetDataByte                     
                       if GetDataByte == 13
                          ChangePort
                    if Rx == "E"
                       Channel := GetDataByte                      
                       if GetDataByte == 13
                          Channel := 0#>Channel<#31 
                          PortRequest := (Channel & %10000)>>4
                          If PortDetect == PortRequest
                             Channel &= %01111 
                             EnableServo                '' Enable specific servo
                    if Rx == "D"
                       Channel := GetDataByte                      
                       if GetDataByte == 13
                          Channel := 0#>Channel<#31 
                          PortRequest := (Channel & %10000)>>4
                          If PortDetect == PortRequest
                             Channel &= %01111 
                             DisableServo               '' Disable specific servo

PUB SerialIndicator(_TX,_RX,S,Activity)|OldTX,OldRX,OldS
    DIRA[Activity]~~                                    '' Make Activity pin an Output
    repeat

      if OldS<>ina[S]                                   '' Check Serial RX and TX line for activity 
         OldS := ina[S]
         OutA[Activity]~~
         repeat 1000
      else   
         OutA[Activity]~

      if OldTX<>ina[_TX]                                 '' Check USB TX line for activity 
         OldTX := ina[_TX]
         OutA[Activity]~~
         repeat 1000
      else   
         OutA[Activity]~
                  
      if OldRX<>ina[_RX]                                 '' Check USB RX line for activity 
         OldRX := ina[_RX]
         OutA[Activity]~~
         repeat 1000
      else   
         OutA[Activity]~

PUB GetDataByte|Flag,Data,_Rx   '' Retrieves serial data BYTE from two seperate locations
    Flag := 0                   '  Note: Only one serial data channel should be
    repeat while Flag == 0      '        active at a time and should be read as
      Data := COMport1.rxcheck  '        an either/or but not both.
      if Data <> -1
         _Rx := Data
         Flag := 1
      Data := COMport2.rxcheck
      if Data <> -1
         _Rx := Data
         Flag := 1     
    Result := _Rx

PUB SendDataByte(Data)          '' Sends a serial data BYTE to two seperate locations
    if ina[USB_Rx] == 0         '' Check to see if USB port is powered
       outa[USB_Tx] := 0        '' Force Propeller Tx line LOW if USB not connected
    else
       COMport1.tx(Data)
    COMport2.tx(Data)

PUB SendDataString(Data)        '' Sends a serial data STRING to two seperate locations
    if ina[USB_Rx] == 0         '' Check to see if USB port is powered
       outa[USB_Tx] := 0        '' Force Propeller Tx line LOW if USB not connected
    else
       COMport1.str(Data)
    COMport2.str(Data)

PUB VersionRequest
    if U_Flag == 0               '' Normal version reply
       SendDataString(string("1.0"))
    else                           
       U_Flag := 0               '' Make the PSC compatible with the PSCI
       SendDataString(string("!SCVER?",13,"1.0"))

PUB ChangeBaud                  '' Change baud on two seperate serial channels
    BaudMode := 0 #> BaudMode <# 1
    if ina[USB_Rx] == 0         '' Check to see if USB port is powered
       outa[USB_Tx] := 0        '' Force Propeller Tx line LOW if USB not connected
    else
       COMport1.stop
    COMport2.stop
    Baud := 2400       
    If BaudMode == 1
       Baud := 38400 
    if ina[USB_Rx] == 0         '' Check to see if USB port is powered
       outa[USB_Tx] := 0        '' Force Propeller Tx line LOW if USB not connected
    else
       COMport1.start(31, 30, 0, Baud)
    COMport2.start(27, 27, %0100, Baud)       
    SendDataString(string("BR"))
    SendDataByte(BaudMode)

PUB SetServoPosition            '' Set a new servo position
    Ramp := 0#>Ramp<#63
    If ((Enabled & |<Channel)>>Channel) == 1     '' Check if servo is enabled
       Servo.Set(Channel,0)        '' Disable Servo if servo flag is disabled 
    else
       If ServoRamp[Channel] == 0
          Servo.Set(Channel,500#> PW*2 <# 2500)
       Servo.SetRamp(Channel,500#> PW*2 <# 2500,RampSpeed[Ramp])
    ServoRamp[Channel] := Ramp
    ServoPosition[Channel] := PW   

PUB ReadServoPosition           '' Read Current servo position
    PW := ServoPosition[Channel]
    SendDataByte(Channel)          
    SendDataByte(PW_highbyte)    
    SendDataByte(PW_lowbyte)

PUB ChangePort|t1               '' Change Servo Port
    PortMode := 0 #> PortMode <# 1
                                '' PortMode = 0 ; Enable Port 0 to 15 on startup
                                '' PortMode = 1 ; Enable Port 16 to 31 on startup
    EEPROM.ByteWrite(SoftwareSwitch,LoadDetect<<1+PortMode)
    SendDataString(string("PM"))
    SendDataByte(PortMode)

PUB EnableServo|t1              '' Enable Selected Servo
    t1 := |< Channel 
    Enabled &=  !t1             '' Enable Channel by making coresponding bit LOW
    PW := Enabled
    Servo.SetRamp(Channel,500#> PW*2 <# 2500,RampSpeed[Ramp])
    EEPROM.ByteWrite(EnabledIOs+0,PW_highbyte)
    EEPROM.ByteWrite(EnabledIOs+1,PW_lowbyte)   
    Ramp := 0
    if ServoPosition[Channel] == 0
       PW := 750
    else
       PW := ServoPosition[Channel]
    SetServoPosition

PUB DisableServo|t1  
    t1 := |< Channel           '' Disable Selected Servo 
    Enabled |= t1               '' Disable Channel by making coresponding bit HIGH
    PW := Enabled
    EEPROM.ByteWrite(EnabledIOs+0,PW_highbyte)
    EEPROM.ByteWrite(EnabledIOs+1,PW_lowbyte)
    PW := ServoPosition[Channel]
    Servo.Set(Channel,0)

PUB ToggleServo|t1,channelEnable
    t1 := |< Channel
    channelEnable := Enabled & t1
    if channelEnable
      EnableServo
    else
      DisableServo
PUB GoCCW|t1,channelEnable
    t1 := |< Channel
    channelEnable := Enabled & t1
    if channelEnable
      EnableServo
    PW := 760 + Speed
  ''  if Speed == 0
  ''    DisableServo
  ''  else
      SetServoPosition
PUB GoCW|t1,channelEnable
    t1 := |< Channel
    channelEnable := Enabled & t1
    if channelEnable
      EnableServo
    PW := 760 - Speed
  ''  if Speed == 0
  ''    DisableServo
  ''  else  
      SetServoPosition
PUB GoStop|t1
    t1 := |< Channel
    DisableServo
PUB IncreaseSpeed
    Speed += 25
    Speed := 0#>Speed<#100
PUB DecreaseSpeed
    Speed -= 25
    Speed := 0#>Speed<#100
PUB ZeroSpeed
    Speed := 0
PUB Default_or_Defined          '' Select default (1500us) startup servo position           
                                '' or user defined startup servo position
    LoadDetect := 0#>LoadDetect<#1
                                '' LoadDetect = 0 : Enable default Servo position on startup
                                '' LoadDetect = 1 : Enable defined Servo position on startup    
    EEPROM.ByteWrite(SoftwareSwitch,LoadDetect<<1+PortMode)
    SendDataString(string("DL"))
    SendDataByte(LoadDetect)

PUB DefinedServoValue           '' Set startup user defined servo position in memory
    EEPROM.ByteWrite(ServoCh0 + Channel<<1 +0,PW_highbyte)                        
    EEPROM.ByteWrite(ServoCh0 + Channel<<1 +1,PW_lowbyte)     

PUB CheckUpperEEPROM|i,flag     '' Check EEPROM to see if it has ever been initialized and
    flag := 0                   '' initialize if it hasn't been done.
    repeat i from 0 to 5
      if EEPROM.RandomRead(EEPR0M+i)<>Initialized[i]
         flag := 1
    if flag == 1
       ClearUpperEEPROM

PUB ClearUpperEEPROM|i 
    repeat i from 0 to 5
      EEPROM.ByteWrite(EEPR0M+i,Initialized[i])
    repeat i from 0 to 40
      EEPROM.ByteWrite($8000+i,0)   

DAT

PW            word              'Servo position data
PW_lowbyte    byte      0
PW_highbyte   byte      0

DAT

'' Lookup table for Speeds 0 to 63

'Note: A formula can be applied that will produce values that are within 6.27%
'
'      For ramp speeds between 7 and 63 ...
'
'      RampSpeed = ((Speed - 6)* 70231)/1600
'
'      For speeds between 1 and 6, a polynomial fit could be used to produce
'      values that are within 3.1%, but with as few numbers that are used you
'      don't really gain much by not using a lookup table...
'
'      RampSpeed = (158 * Speed^3 - 742 * Speed^2 + 2888 * Speed + 9264)/1600
'
'Note:
'      RampSpeed - is equal to the delay from one Servo Increment to the next.  The resolution
'                  of the delay is 20ms, so a value of 50 = 1 second ; a value of 3000 = 1 minute 

RampSpeed     word      1,7,8,10,12,16,22,43,83,123,184,222,261,299,339,379,426,473,520,567,615
              word      662,709,756,808,859,910,961,1012,1064,1115,1166,1207,1248,1288,1329,1370
              word      1411,1451,1492,1533,1574,1614,1655,1696,1737,1778,1818,1859,1900,1941,1981
              word      2022,2063,2104,2144,2185,2226,2267,2307,2348,2389,2430,2470

Initialized   byte      "EEPROM"
             
DAT
{{
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}       