import os, json, base64, hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad
from dotenv import load_dotenv

# 加载 .env
load_dotenv()
SCRIPT_KEY = os.getenv("SCRIPT_KEY")
if not SCRIPT_KEY:
    print("请先设置环境变量 SCRIPT_KEY")
    exit(1)

# 生成 32 字节 key (sha256)
key = hashlib.sha256(SCRIPT_KEY.encode()).digest()

# 生成随机 IV
iv = os.urandom(16)

# 读取要加密的脚本
with open("s5_source.py", "r", encoding="utf-8") as f:
    code = f.read()

# AES-256-CBC 加密，输出 base64
cipher = AES.new(key, AES.MODE_CBC, iv)
encrypted = cipher.encrypt(pad(code.encode("utf-8"), AES.block_size))

encrypted_obj = {
    "iv": base64.b64encode(iv).decode(),
    "data": base64.b64encode(encrypted).decode()
}

# 写入 s5.enc
with open("s5.enc", "w", encoding="utf-8") as f:
    json.dump(encrypted_obj, f, indent=2)

print("✅ s5_source.py 已加密生成 s5.enc")
