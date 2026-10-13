"""
Autoriza el acceso a Google Drive UNA sola vez.
Corre esto en tu Mac (no en el servidor), genera token.json, y sube ese
archivo al servidor.

Requisitos:
  pip install google-auth-oauthlib google-api-python-client
  y tener credentials.json (de console.cloud.google.com) en la misma carpeta.
"""
from google_auth_oauthlib.flow import InstalledAppFlow

# Permiso para subir archivos a Drive
SCOPES = ["https://www.googleapis.com/auth/drive.file"]


def main():
    flow = InstalledAppFlow.from_client_secrets_file("credentials.json", SCOPES)
    creds = flow.run_local_server(port=0)  # abre el navegador para autorizar
    with open("token.json", "w") as f:
        f.write(creds.to_json())
    print("Listo. Se generó token.json — súbelo al servidor en /opt/finbot/")


if __name__ == "__main__":
    main()
