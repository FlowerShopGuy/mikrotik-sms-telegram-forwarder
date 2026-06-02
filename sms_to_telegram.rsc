# ==============================================================================
# SMS to Telegram Forwarding Script (Smart Concatenation + Auto-detect + Tagging + 7bit UDH Fix)
# ==============================================================================

# --- SETTINGS BLOCK ---
:local botToken "YOUR_BOT_TOKEN_HERE"
:local chatId "YOUR_CHAT_ID_HERE"

:local autoDetectPort true
:local usbPort "usb1"

# List of suspicious numbers (comma-separated, no spaces)
:local suspiciousNumbers "888,000"
# ---------------------

:local ucs2ToUrlEncode do={
    :local hexChars "0123456789ABCDEF"; :local result ""
    :for i from=0 to=([:len $1] - 1) step=4 do={
        :local hexVal [:tonum ("0x" . [:pick $1 $i ($i + 4)])]
        :if ($hexVal < 0x80) do={ :set result ($result . "%" . [:pick $hexChars ($hexVal / 16)] . [:pick $hexChars ($hexVal % 16)]) }
        :if (($hexVal >= 0x80) and ($hexVal < 0x800)) do={
            :local b1 (($hexVal >> 6) | 192); :local b2 (($hexVal & 63) | 128)
            :set result ($result . "%" . [:pick $hexChars ($b1 / 16)] . [:pick $hexChars ($b1 % 16)] . "%" . [:pick $hexChars ($b2 / 16)] . [:pick $hexChars ($b2 % 16)])
        }
        :if ($hexVal >= 0x800) do={
            :local b1 (($hexVal >> 12) | 224); :local b2 ((($hexVal >> 6) & 63) | 128); :local b3 (($hexVal & 63) | 128)
            :set result ($result . "%" . [:pick $hexChars ($b1 / 16)] . [:pick $hexChars ($b1 % 16)] . "%" . [:pick $hexChars ($b2 / 16)] . [:pick $hexChars ($b2 % 16)] . "%" . [:pick $hexChars ($b3 / 16)] . [:pick $hexChars ($b3 % 16)])
        }
    }
    :return $result
}

:local unpack7bit do={
    :local hexChars "0123456789ABCDEF"; :local result ""; :local shift 0; :local carry 0
    :for i from=0 to=([:len $1] - 1) step=2 do={
        :local byte [:tonum ("0x" . [:pick $1 $i ($i + 2)])]
        :local septet ((($byte << $shift) | $carry) & 127)
        :set carry ($byte >> (7 - $shift)); :set shift ($shift + 1)
        :if ($septet = 0) do={ :set septet 64 }
        :if ($septet = 2) do={ :set septet 36 }
        :if ($septet = 17) do={ :set septet 95 }
        :set result ($result . "%" . [:pick $hexChars ($septet / 16)] . [:pick $hexChars ($septet % 16)])
        :if ($shift = 7) do={
            :local septet2 ($carry & 127)
            :if ($septet2 > 0) do={
                :if ($septet2 = 0) do={ :set septet2 64 }; :if ($septet2 = 2) do={ :set septet2 36 }; :if ($septet2 = 17) do={ :set septet2 95 }
                :set result ($result . "%" . [:pick $hexChars ($septet2 / 16)] . [:pick $hexChars ($septet2 % 16)])
            }
            :set shift 0; :set carry 0
        }
    }
    :return $result
}

:local fSwap do={
    :local res ""
    :for i from=0 to=([:len $1] - 1) step=2 do={ :set res ($res . [:pick $1 ($i + 1)] . [:pick $1 $i]) }
    :return $res
}

# --- MAIN ROUTINE ---
:log info "TG_SMS: Script started..."

:local pppInt ""
:if ($autoDetectPort = true) do={
    :set pppInt [[:toarray [/interface ppp-client find]] -> 0]
} else={
    :set pppInt [/interface ppp-client find port=$usbPort]
}

:if ([:len $pppInt] = 0) do={
    :log error "TG_SMS: Error. PPP Client interface not found."
} else={
    :local modemInt [/interface ppp-client get $pppInt name]
    
    /interface ppp-client at-chat $modemInt input="AT+CMGF=0" as-value
    :delay 1s
    
    :local raw [/interface ppp-client at-chat $modemInt input="AT+CMGL=4" as-value]
    :local content ($raw->"output")
    :local start [:find $content "+CMGL:"]
    
    :if ([:typeof $start] = "nil") do={
        :log info "TG_SMS: No messages in the modem."
    } else={
        :local parsedList [:toarray ""]

        :while ([:typeof $start] = "num") do={
            :local endLine [:find $content "\r\n" $start]
            :local idxEnd [:find $content "," ($start + 7)]
            :local smsIdx [:tonum [:pick $content ($start + 7) $idxEnd]]
            
            :local pduStart ($endLine + 2)
            :local pduEnd [:find $content "\r\n" $pduStart]
            :local pdu [:pick $content $pduStart $pduEnd]
            
            :local scaLen ([:tonum ("0x" . [:pick $pdu 0 2])] * 2 + 2)
            :local tpdu [:pick $pdu $scaLen [:len $pdu]]
            
            :local oaLenHex [:tonum ("0x" . [:pick $tpdu 2 4])]
            :if ($oaLenHex % 2 != 0) do={ :set oaLenHex ($oaLenHex + 1) }
            
            :local oaType [:pick $tpdu 4 6]
            :local rawPhone [:pick $tpdu 6 (6 + $oaLenHex)]
            :local typeOfNum (([:tonum ("0x" . $oaType)] >> 4) & 7)
            :local safePhone ""
            
            :if ($typeOfNum = 5) do={
                :set safePhone [$unpack7bit $rawPhone]
            } else={
                :local phone [$fSwap $rawPhone]
                :if ([:pick $phone ([:len $phone] - 1)] = "F") do={ :set phone [:pick $phone 0 ([:len $phone] - 1)] }
                :if ($typeOfNum = 1) do={ :set safePhone ("%2B" . $phone) } else={ :set safePhone $phone }
            }
            
            :local rawTime [:pick $tpdu (10 + $oaLenHex) (24 + $oaLenHex)]
            :local swTime [$fSwap $rawTime]
            :local safeTime ("20" . [:pick $swTime 0 2] . "-" . [:pick $swTime 2 4] . "-" . [:pick $swTime 4 6] . "%20" . [:pick $swTime 6 8] . ":" . [:pick $swTime 8 10] . ":" . [:pick $swTime 10 12])
            
            :local pduType [:tonum ("0x" . [:pick $tpdu 0 2])]
            :local udhi (($pduType >> 6) & 1)
            
            :local dcsHex [:tonum ("0x" . [:pick $tpdu (8 + $oaLenHex) (10 + $oaLenHex)])]
            :local alphabet ((($dcsHex >> 2) & 3))
            :local isUcs2 false
            :local is8bit false
            :if ($alphabet = 2) do={ :set isUcs2 true }
            :if ($alphabet = 1) do={ :set is8bit true }
            
            :local udStart (26 + $oaLenHex)
            :local isMulti false; :local refNum 0; :local totalParts 1; :local currentPart 1
            
            # --- 7-BIT ALIGNMENT LOGIC ---
            :local ucs2Start $udStart
            :local septetsToSkip 0
            
            :if ($udhi = 1) do={
                :local udhl [:tonum ("0x" . [:pick $tpdu $udStart ($udStart + 2)])]
                :local iei [:pick $tpdu ($udStart + 2) ($udStart + 4)]
                :if ($iei = "00") do={
                    :set isMulti true
                    :set refNum [:tonum ("0x" . [:pick $tpdu ($udStart + 6) ($udStart + 8)])]
                    :set totalParts [:tonum ("0x" . [:pick $tpdu ($udStart + 8) ($udStart + 10)])]
                    :set currentPart [:tonum ("0x" . [:pick $tpdu ($udStart + 10) ($udStart + 12)])]
                }
                :if ($iei = "08") do={
                    :set isMulti true
                    :set refNum [:tonum ("0x" . [:pick $tpdu ($udStart + 6) ($udStart + 10)])]
                    :set totalParts [:tonum ("0x" . [:pick $tpdu ($udStart + 10) ($udStart + 12)])]
                    :set currentPart [:tonum ("0x" . [:pick $tpdu ($udStart + 12) ($udStart + 14)])]
                }
                
                :set ucs2Start ($udStart + 2 + $udhl * 2)
                :local totalUdhBytes ($udhl + 1)
                :set septetsToSkip ((($totalUdhBytes * 8) + 6) / 7)
            }
            
            :local decodedMsg ""
            :if ($isUcs2 = true) do={ 
                :set decodedMsg [$ucs2ToUrlEncode [:pick $tpdu $ucs2Start [:len $tpdu]]] 
            } else={ 
                # Unpacking the ENTIRE data block along with the header to preserve the 7-bit grid step
                :local full7bit [$unpack7bit [:pick $tpdu $udStart [:len $tpdu]]]
                # Skipping header service characters (each UrlEncode character takes 3 chars, e.g., %20)
                :local charsToSkip ($septetsToSkip * 3)
                :set decodedMsg [:pick $full7bit $charsToSkip [:len $full7bit]]
            }
            # ---------------------------------
            
            # --- SPAM AND BINARY DATA TAGGING ---
            :local alertTag ""
            
            :if ($is8bit = true) do={
                :set alertTag "%E2%9A%99%EF%B8%8F%20%5BOPERATOR%20BINARY%20FILE%5D%0A%0A"
            } else={
                :if ([:typeof [:find ("," . $suspiciousNumbers . ",") ("," . $safePhone . ",")]] = "num") do={
                    :set alertTag "%E2%9A%A0%EF%B8%8F%20%5BSUSPICIOUS%20NUMBER%5D%0A%0A"
                }
            }
            
            :set decodedMsg ($alertTag . $decodedMsg)
            # ----------------------------------------
            
            :set parsedList ($parsedList , {{"idx"=$smsIdx; "phone"=$safePhone; "time"=$safeTime; "multi"=$isMulti; "ref"=$refNum; "total"=$totalParts; "part"=$currentPart; "text"=$decodedMsg}})
            
            :set start [:find $content "+CMGL:" $pduEnd]
        }
        
        :local handledRefs ","
        :foreach msg in=$parsedList do={
            :if ([:typeof $msg] = "array") do={
                
                :local curPhone ($msg->"phone")
                :local curTime ($msg->"time")
                :local curText ($msg->"text")
                
                :if (($msg->"multi") = false) do={
                    :local headerText "%E2%9C%89%EF%B8%8F%20New%20SMS%3A%0A%F0%9F%93%B1%20From%3A%20$curPhone%0A%F0%9F%93%85%20Time%3A%20$curTime%0A%0A"
                    :local postData "chat_id=$chatId&text=$headerText$curText"
                    
                    :do {
                        /tool fetch url="https://api.telegram.org/bot$botToken/sendMessage" http-method=post http-data=$postData keep-result=no
                        /interface ppp-client at-chat $modemInt input=("AT+CMGD=" . ($msg->"idx"))
                        :delay 2s
                    } on-error={ :log error "TG_SMS: Error communicating with Telegram API." }
                } else={
                    :local ref ($msg->"ref")
                    :if ([:typeof [:find $handledRefs ("," . $ref . ",")]] = "nil") do={
                        :local total ($msg->"total")
                        :local foundParts 0
                        :local combinedText ""
                        :local idxsToDelete [:toarray ""]
                        
                        :for i from=1 to=$total do={
                            :foreach m in=$parsedList do={
                                :if ([:typeof $m] = "array") do={
                                    :if ((($m->"ref") = $ref) and (($m->"part") = $i)) do={
                                        :set foundParts ($foundParts + 1)
                                        :set combinedText ($combinedText . ($m->"text"))
                                        :set idxsToDelete ($idxsToDelete , ($m->"idx"))
                                    }
                                }
                            }
                        }
                        
                        :if ($foundParts = $total) do={
                            :local headerText "%E2%9C%89%EF%B8%8F%20Long%20SMS%3A%0A%F0%9F%93%B1%20From%3A%20$curPhone%0A%F0%9F%93%85%20Time%3A%20$curTime%0A%0A"
                            :local postData "chat_id=$chatId&text=$headerText$combinedText"
                            
                            :do {
                                /tool fetch url="https://api.telegram.org/bot$botToken/sendMessage" http-method=post http-data=$postData keep-result=no
                                
                                :foreach delIdx in=$idxsToDelete do={
                                    :if ([:typeof $delIdx] = "num") do={
                                        /interface ppp-client at-chat $modemInt input=("AT+CMGD=" . $delIdx)
                                        :delay 1s
                                    }
                                }
                            } on-error={ :log error "TG_SMS: Error communicating with Telegram API during concatenation." }
                            
                            :set handledRefs ($handledRefs . $ref . ",")
                        }
                    }
                }
            }
        }
    }
}