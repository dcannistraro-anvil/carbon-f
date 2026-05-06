# Customer and Supplier Database Schema in Carbon

## Overview

The Carbon system uses PostgreSQL (via Supabase) to store customer and supplier information across multiple related tables with comprehensive relationship management and audit trails.

## Core Customer Tables

### `customer` Table (Main Entity)

**Primary Fields:**
- `id` TEXT PRIMARY KEY (UUID, auto-generated)
- `name` TEXT NOT NULL (unique per company)
- `customerTypeId` TEXT (FK to customerType.id)
- `customerStatusId` TEXT (FK to customerStatus.id)
- `taxId` TEXT (tax identification number)
- `accountManagerId` TEXT (FK to user.id)
- `logo` TEXT (logo URL/path)
- `assignee` TEXT (FK to user.id)

**Contact Information (added in later migrations):**
- `phone` TEXT
- `fax` TEXT
- `website` TEXT
- `currencyCode` TEXT (FK to currencyCode.code)

**Audit Fields:**
- `companyId` TEXT NOT NULL (FK to company.id)
- `createdAt` TIMESTAMP WITH TIME ZONE DEFAULT NOW()
- `createdBy` TEXT (FK to user.id)
- `updatedAt` TIMESTAMP WITH TIME ZONE
- `updatedBy` TEXT (FK to user.id)
- `customFields` JSONB (extensible custom data)

### `customerType` Table (Classification)

**Fields:**
- `id` TEXT PRIMARY KEY (UUID)
- `name` TEXT NOT NULL (unique per company)
- `protected` BOOLEAN DEFAULT FALSE
- Standard audit fields (companyId, createdBy, updatedBy, etc.)
- `customFields` JSONB

### `customerStatus` Table (Status Tracking)

**Fields:**
- `id` TEXT PRIMARY KEY (id)
- `name` TEXT NOT NULL (unique per company)
- Standard audit fields (companyId, createdBy, updatedBy, etc.)
- `customFields` JSONB

## Customer Related Tables

### `customerLocation` Table (Address Management)

**Fields:**
- `id` TEXT PRIMARY KEY (id)
- `customerId` TEXT NOT NULL (FK to customer.id)
- `addressId` TEXT NOT NULL (FK to address.id)
- `name` TEXT NOT NULL (location name, added in later migration)
- `customFields` JSONB

### `customerContact` Table (Contact Management)

**Fields:**
- `id` TEXT PRIMARY KEY (id)
- `customerId` TEXT NOT NULL (FK to customer.id)
- `contactId` TEXT NOT NULL (FK to contact.id)
- `customerLocationId` TEXT (FK to customerLocation.id, optional)
- `userId` TEXT (FK to user.id, optional - for user-linked contacts)
- `customFields` JSONB

### `customerPayment` Table (Payment Settings)

**Fields:**
- `customerId` TEXT PRIMARY KEY (1:1 with customer)
- `invoiceCustomerId` TEXT (FK to customer.id - can be different for billing)
- `invoiceCustomerLocationId` TEXT (FK to customerLocation.id)
- `invoiceCustomerContactId` TEXT (FK to customerContact.id)
- `paymentTermId` TEXT (FK to paymentTerm.id)
- `currencyCode` TEXT (FK to currency table)
- `companyId` TEXT NOT NULL
- Standard update audit fields

### `customerShipping` Table (Shipping Settings)

**Fields:**
- `customerId` TEXT PRIMARY KEY (1:1 with customer)
- `shippingCustomerId` TEXT (FK to customer.id - can be different for shipping)
- `shippingCustomerLocationId` TEXT (FK to customerLocation.id)
- `shippingCustomerContactId` TEXT (FK to customerContact.id)
- `shippingTermId` TEXT (FK to shippingTerm.id)
- `shippingMethodId` TEXT (FK to shippingMethod.id)
- `companyId` TEXT NOT NULL
- Standard update audit fields

### `customerAccount` Table (User Access)

**Fields:**
- `id` TEXT (FK to user.id)
- `customerId` TEXT NOT NULL (FK to customer.id)
- `companyId` TEXT NOT NULL
- Composite primary key: (id, companyId)

## Core Supplier Tables

### `supplier` Table (Main Entity)

**Primary Fields:**
- `id` TEXT PRIMARY KEY (UUID, auto-generated)
- `name` TEXT NOT NULL (unique per company)
- `supplierTypeId` TEXT (FK to supplierType.id)
- `supplierStatusId` TEXT (FK to supplierStatus.id)
- `taxId` TEXT (tax identification number)
- `accountManagerId` TEXT (FK to user.id)
- `logo` TEXT (logo URL/path)
- `assignee` TEXT (FK to user.id)

**Contact Information (added in later migrations):**
- `phone` TEXT
- `fax` TEXT
- `website` TEXT
- `currencyCode` TEXT (FK to currencyCode.code)

**Audit Fields:**
- `companyId` TEXT NOT NULL (FK to company.id)
- `createdAt` TIMESTAMP WITH TIME ZONE DEFAULT NOW()
- `createdBy` TEXT (FK to user.id)
- `updatedAt` TIMESTAMP WITH TIME ZONE
- `updatedBy` TEXT (FK to user.id)
- `customFields` JSONB (extensible custom data)

### `supplierType` Table (Classification)

**Fields:**
- `id` TEXT PRIMARY KEY (UUID)
- `name` TEXT NOT NULL (unique per company)
- `protected` BOOLEAN DEFAULT FALSE
- Standard audit fields (companyId, createdBy, updatedBy, etc.)
- `customFields` JSONB

### `supplierStatus` Table (Status Tracking)

**Fields:**
- `id` TEXT PRIMARY KEY (id)
- `name` TEXT NOT NULL (unique per company)
- Standard audit fields (companyId, createdBy, updatedBy, etc.)
- `customFields` JSONB

## Supplier Related Tables

### `supplierLocation` Table (Address Management)

**Fields:**
- `id` TEXT PRIMARY KEY (id)
- `supplierId` TEXT NOT NULL (FK to supplier.id)
- `addressId` TEXT NOT NULL (FK to address.id)
- `name` TEXT NOT NULL (location name, added in later migration)
- `customFields` JSONB

### `supplierContact` Table (Contact Management)

**Fields:**
- `id` TEXT PRIMARY KEY (id)
- `supplierId` TEXT NOT NULL (FK to supplier.id)
- `contactId` TEXT NOT NULL (FK to contact.id)
- `supplierLocationId` TEXT (FK to supplierLocation.id, optional)
- `userId` TEXT (FK to user.id, optional - for user-linked contacts)
- `customFields` JSONB

### `supplierPayment` Table (Payment Settings)

**Fields:**
- `supplierId` TEXT PRIMARY KEY (1:1 with supplier)
- `invoiceSupplierId` TEXT (FK to supplier.id - can be different for billing)
- `invoiceSupplierLocationId` TEXT (FK to supplierLocation.id)
- `invoiceSupplierContactId` TEXT (FK to supplierContact.id)
- `paymentTermId` TEXT (FK to paymentTerm.id)
- `currencyCode` TEXT (FK to currency table)
- `companyId` TEXT NOT NULL
- Standard update audit fields
- `customFields` JSONB

### `supplierShipping` Table (Shipping Settings)

**Fields:**
- `supplierId` TEXT PRIMARY KEY (1:1 with supplier)
- `shippingSupplierId` TEXT (FK to supplier.id - can be different for shipping)
- `shippingSupplierLocationId` TEXT (FK to supplierLocation.id)
- `shippingSupplierContactId` TEXT (FK to supplierContact.id)
- `shippingTermId` TEXT (FK to shippingTerm.id)
- `shippingMethodId` TEXT (FK to shippingMethod.id)
- `companyId` TEXT NOT NULL
- Standard update audit fields
- `customFields` JSONB

### `supplierAccount` Table (User Access)

**Fields:**
- `id` TEXT (FK to user.id)
- `supplierId` TEXT NOT NULL (FK to supplier.id)
- `companyId` TEXT NOT NULL
- Composite primary key: (id, companyId)

## Shared Supporting Tables

### `contact` Table (Contact Information)

**Fields:**
- `id` TEXT PRIMARY KEY (id)
- `firstName` TEXT NOT NULL
- `lastName` TEXT NOT NULL
- `fullName` TEXT GENERATED (firstName + ' ' + lastName)
- `email` TEXT NOT NULL
- `title` TEXT (job title)
- `mobilePhone` TEXT
- `homePhone` TEXT
- `workPhone` TEXT
- `fax` TEXT
- `addressLine1` TEXT
- `addressLine2` TEXT
- `city` TEXT
- `state` TEXT
- `postalCode` TEXT
- `countryCode` INTEGER (FK to country.id)
- `birthday` DATE
- `notes` TEXT
- `companyId` TEXT NOT NULL

### `address` Table (Address Information)

**Fields:**
- `id` TEXT PRIMARY KEY (id)
- `addressLine1` TEXT
- `addressLine2` TEXT
- `city` TEXT
- `state` TEXT
- `postalCode` TEXT
- `countryCode` INTEGER (FK to country.id)
- `phone` TEXT
- `fax` TEXT
- `companyId` TEXT NOT NULL

## Database Views

### `customers` View

Aggregated view that includes:
- All customer table fields
- `type` (from customerType.name)
- `status` (from customerStatus.name)
- `orderCount` (count of sales orders)

### `suppliers` View

Aggregated view that includes:
- All supplier table fields
- `type` (from supplierType.name)
- `status` (from supplierStatus.name)
- `orderCount` (count of purchase orders)
- `partCount` (count of supplier parts/buy methods)

## Key Features

### Automatic Entry Creation

When a customer or supplier is created, triggers automatically create:
- Payment settings record (customerPayment/supplierPayment)
- Shipping settings record (customerShipping/supplierShipping)

### Custom Fields Support

Both customers and suppliers support:
- JSONB `customFields` on main entities and related tables
- Custom field type system via `attributeDataType` table
- Specific customer and supplier attribute data types

### Multi-tenancy

- All tables are scoped by `companyId`
- Row Level Security (RLS) policies enforce data isolation
- Unique constraints are per-company (e.g., customer name unique per company)

### Audit Trail

- Standard created/updated by/at fields on all main entities
- Change tracking for all updates
- User attribution for all modifications

## Migration History

Key migrations that built this schema:
- `20230123004612_suppliers-and-customers.sql` - Core tables
- `20231109050252_customer-details.sql` - Payment/shipping tables
- `20231109050239_supplier-details.sql` - Supplier payment/shipping
- `20241009181230_customer-supplier-additional-fields.sql` - Contact info
- `20240813213122_add-customer-supplier-location-name.sql` - Location names
- `20250125121403_add-customer-and-supplier-custom-fields.sql` - Custom fields