import 'dotenv/config'

export interface AppConfig {
  port: number
  databaseUrl: string
  jwtSecret: string
  licensePrivateKeyB64?: string
  licensePublicKeyB64?: string
  adminEmail?: string
  adminPassword?: string
}

export const config: AppConfig = {
  port: parseInt(process.env.PORT || '8080', 10),
  databaseUrl:
    process.env.DATABASE_URL ||
    'mysql://root:password@127.0.0.1:3306/license_db?timezone=Z',
  jwtSecret: process.env.JWT_SECRET || 'change-me-in-prod',
  licensePrivateKeyB64: process.env.LICENSE_PRIVATE_KEY,
  licensePublicKeyB64: process.env.LICENSE_PUBLIC_KEY,
  adminEmail: process.env.ADMIN_EMAIL,
  adminPassword: process.env.ADMIN_PASSWORD,
}


