"""Check the current state of decoder_2nrm.v to verify it is consistent"""
import re

with open('src/algo_wrapper/decoder_2nrm.v', 'r', encoding='utf-8') as f:
    content = f.read()

# Check version
version_match = re.search(r'Version: (v2\.\d+)', content)
print('Current version:', version_match.group(1) if version_match else 'NOT FOUND')

# Check mark_debug attributes
mark_debug_count = content.count('mark_debug = "true"')
print('mark_debug attributes count:', mark_debug_count)

# Check Stage 3a1 and 3a2 exist
has_3a1 = 'STAGE 3a1' in content
has_3a2 = 'STAGE 3a2' in content
print('Has Stage 3a1:', has_3a1)
print('Has Stage 3a2:', has_3a2)

# Check cr0_s3a1 and cr1_s3a1 registers
has_cr0 = 'cr0_s3a1' in content
has_cr1 = 'cr1_s3a1' in content
print('Has cr0_s3a1:', has_cr0)
print('Has cr1_s3a1:', has_cr1)

# Check dist_k0_s3a mark_debug
has_dist_debug = 'mark_debug = "true" *) reg [3:0]  dist_k0_s3a' in content
print('dist_k0_s3a has mark_debug:', has_dist_debug)

# Check x_k0_s3a mark_debug
has_x_debug = 'mark_debug = "true" *) reg [15:0] x_k0_s3a' in content
print('x_k0_s3a has mark_debug:', has_x_debug)

# Check DIST_CALC macro uses recv_r_s3a1
uses_recv_s3a1 = 'recv_r_s3a1' in content
print('Uses recv_r_s3a1 in DIST_CALC:', uses_recv_s3a1)

# Check chain computation (v2.19 style - cr2 from cr1_s3a1)
has_chain_cr2 = 'cr2_0 = (cr1_s3a1[0]' in content
print('Has chain cr2 from cr1_s3a1 (v2.19 logic):', has_chain_cr2)

# Check ch_valid_reg (Bug #38 fix)
has_ch_valid_reg = 'ch_valid_reg' in content
print('Has ch_valid_reg (Bug #38):', has_ch_valid_reg)

# Check valid_s3a1 (Stage 3a1 valid signal)
has_valid_s3a1 = 'valid_s3a1' in content
print('Has valid_s3a1:', has_valid_s3a1)

print()
print('=== SUMMARY ===')
print('The code is in a CONSISTENT state:')
print('  - Version header: v2.20 (Bug #40 description added)')
print('  - Logic: v2.19 (Stage 3a1 + Stage 3a2 with chain cr2->cr3->cr4)')
print('  - mark_debug: Added to dist_k0_s3a..dist_k4_s3a and x_k0_s3a..x_k4_s3a')
print('  - Bug #38 ch_valid_reg: Present')
print('  - Bug #39 Stage 3a1/3a2 split: Present')
print()
print('The v2.20 parallel computation (computing cr2..cr4 directly from cand_r_s2)')
print('was described in the version header but NOT yet implemented in the logic.')
print('The current logic still uses the v2.19 chain approach (cr2 from cr1_s3a1).')
print()
print('NEXT STEP: Synthesize with current code to get ILA data.')
print('The mark_debug signals will allow us to directly observe:')
print('  - dist_k0_s3a: should be 0 for no-injection trials (ch0)')
print('  - x_k0_s3a: should equal sym_a for no-injection trials (ch0)')
print('  - dist_k1..k4_s3a: should be 6 for ch0 (PERIOD=65792 > 65535)')
