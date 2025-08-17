import os, json, base64, hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad
from dotenv import load_dotenv

load_dotenv()
SCRIPT_KEY = os.getenv("SCRIPT_KEY")
if not SCRIPT_KEY:
    print("请先在 .env 文件里设置 SCRIPT_KEY")
    exit(1)

key = hashlib.sha256(SCRIPT_KEY.encode()).digest()

with open("s5.enc", "r", encoding="utf-8") as f:
    enc_obj = json.load(f)

iv = base64.b64decode(enc_obj["iv"])
data = base64.b64decode(enc_obj["data"])

cipher = AES.new(key, AES.MODE_CBC, iv)
code = unpad(cipher.decrypt(data), AES.block_size).decode("utf-8")

exec(code, globals())
