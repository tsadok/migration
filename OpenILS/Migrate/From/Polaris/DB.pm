# -*- cperl -*-

package OpenILS::Migrate::From::Polaris::DB;
# I found instructions for setting up an ODBC driver on Linux here:
# http://www.easysoft.com/developer/languages/perl/sql_server_unix_tutorial.html
# I used that setup in Galion and it worked, but then the trial license expired,
# so I ended up going with DBD::Sybase and freetds instead, which also works.

use Carp;
use strict;
use DBI;
use Exporter;

our %connectinfo;
our $tables;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION      = 1.00;
@ISA          = qw(Exporter);
@EXPORT       = qw(&connect &getrecord &getsince &findrecord $tables);
@EXPORT_OK    = (%connectinfo);
%EXPORT_TAGS  = ( DEFAULT => [qw(&connect &getrecord &findrecord)],
                  Both    => [(%connectinfo, $tables)]);

my $idtype = "int4"; # Type to use for all Polaris ID and foreign-key fields.

# Note that links only need to be specified here if they are meaningful for
# determining which records to include in active/current data loads; the links
# should be specified from the table that is loaded first, to the later one.
# Tables are specified in the order in which they should be loaded, so the
# ones that define which patrons/items are active must be first.
$tables = +[
  ( +{ name    => "Polaris.Polaris.PolarisUsers",
       # All the CreatorID and ModifierID fields link to this table.
       # Polaris has no mapping from these to the corresponding patron
       # records, so that will have to be supplied separately later.
       idfield => "PolarisUserID",
       migrate => "full",
       fields  => [ +{ name => "PolarisUserID",        type => $idtype, },
                    +{ name => "OrganizationID",       type => $idtype, },
                    +{ name => "Name",                 type => varchar(50)},
                    +{ name => "BranchID",             type => $idtype, },
                    +{ name => "Enabled",              type => "bool", },
                    +{ name => "CreatorID",            type => $idtype, },
                    +{ name => "ModifierID",           type => $idtype, },
                    +{ name => "CreationDate",         type => "timestamp", },
                    +{ name => "ModificationDate",     type => "timestamp", },
                    +{ name => "NetworkDomainID",      type => $idtype, },
                  ],},
    # The ItemCheckouts table is next because in "active records" mode it
    # defines which patrons and which items are considered active.
    +{ name    => "Polaris.Polaris.ItemCheckouts",
       migrate => "full",
       fields  => [ +{ name => "ItemRecordID",         type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.CircItemRecords", f => "ItemRecordID", r => "n-to-one", }], },
                    +{ name => "PatronID",             type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.Patrons", f => "PatronID", r => "n-to-one", },], },
                    +{ name => "OrganizationID",       type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.Organizations", f => "OrganizationID", r => "n-to-one", }], },
                    +{ name => "CreatorID",            type => $idtype, },
                    +{ name => "CheckOutDate",         type => "timestamp" },
                    +{ name => "DueDate",              type => "timestamp" },
                    +{ name => "Renewals",             type => "int2" },
                    +{ name => "OVDNoticeCount",       type => "int2", },
                    +{ name => "RecallFlag",           type => "int2", },
                    +{ name => "RecallDate",           type => "timestamp", },
                    +{ name => "LoanUnits",            type => "int2", },
                    +{ name => "OVDNoticeDate",        type => "timestamp", },
                    +{ name => "BillingNoticeSent",    type => "int2", },
                    +{ name => "OriginalCheckOutDate", type => "timestamp", },
                    +{ name => "OriginalDueDate",      type => "timestamp", },
                    +{ name => "CourseReserveID",      type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.CourseReserves", f => "CourseReserveID", r => "unknown", }]},
                  ],
     },
    #####################################################################################
    ###
    ###  P A T R O N   D A T A
    ###
    #####################################################################################
    +{ name    => "Polaris.Polaris.Patrons",
       idfield => "PatronID",
       migrate => "normal",
       current => "LastActivityDate",
       fields  => [ +{ name => "PatronID",              type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.PatronRegistration",   f => "PatronID", r => "one-to-one", },
                                 +{ t => "Polaris.Polaris.PatronAddresses",      f => "PatronID", r => "one-to-n", },
                                 +{ t => "Polaris.Polaris.PatronStops",          f => "PatronID", r => "n-to-n", },
                                 +{ t => "Polaris.Polaris.PatronFreeTextBlocks", f => "PatronID", r => "n-to-n", },
                                 +{ t => "Polaris.Polaris.PatronNotes",          f => "PatronID", r => "may-have-one", }], },
                    +{ name => "PatronCodeID",          type => $idtype, },
                    +{ name => "OrganizationID",         type => $idtype, },
                    +{ name => "CreatorID",              type => $idtype, },
                    +{ name => "ModifierID",             type => $idtype, },
                    +{ name => "Barcode",                type => varchar(20), },
                    +{ name => "SystemBlocks",           type => "int2", }, # Only one bit (the 128 bit) is actually used, AFAICT.
                    +{ name => "YTDCircCount",           type => "int4", }, # Probably would fit easily in an int2, but let's not scrimp bits.
                    +{ name => "LifetimeCircCount",      type => "int4", },
                    +{ name => "LastActivityDate",       type => "timestamp", },
                    +{ name => "ClaimCount",             type => "int2", },
                    +{ name => "LostItemCount",          type => "int2", },
                    +{ name => "ChargesAmount",          type => "money", },
                    +{ name => "CreditsAmount",          type => "money", },
                  ],},
    +{ name    => "Polaris.Polaris.PatronRegistration",
       idfield => "PatronID",
       migrate => "normal",
       fields  => [ +{ name => "PatronID",              type => $idtype, },
                    +{ name => "LanguageID",            type => $idtype, },
                    +{ name => "NameFirst",             type => varchar(32), },
                    +{ name => "NameLast",              type => varchar(32), },
                    +{ name => "NameMiddle",            type => varchar(32), },
                    +{ name => "NameTitle",             type => varchar(8), },
                    +{ name => "NameSuffix",            type => varchar(4), },
                    +{ name => "PhoneVoice1",           type => varchar(20), },
                    +{ name => "PhoneVoice2",           type => varchar(20), },
                    +{ name => "PhoneVoice3",           type => varchar(20), },
                    +{ name => "EmailAddress",          type => varchar(64), },
                    +{ name => "Password",              type => varchar(16), },
                    +{ name => "EntryDate",             type => "timestamp", },
                    +{ name => "ExpirationDate",        type => "timestamp", },
                    +{ name => "AddrCheckDate",         type => "timestamp", },
                    +{ name => "UpdateDate",            type => "timestamp", },
                    +{ name => "User1",                 type => varchar(64), },
                    +{ name => "User2",                 type => varchar(64), },
                    +{ name => "User3",                 type => varchar(64), },
                    +{ name => "User4",                 type => varchar(64), },
                    +{ name => "User5",                 type => varchar(64), },
                    +{ name => "Gender",                type => char(1), },
                    +{ name => "Birthdate",             type => "timestamp", },
                    +{ name => "RegistrationDate",      type => "timestamp", },
                    +{ name => "FormerID",              type => varchar(20), }, # Actually former barcode
                    +{ name => "ReadingList",           type => "int2", },      # Effectively boolean
                    +{ name => "PhoneFAX",              type => varchar(20), },
                    +{ name => "DeliveryOptionID",      type => $idtype, },
                    +{ name => "StatisticalClassID",    type => $idtype, },
                    +{ name => "CollectionExempt",      type => "bool", },
                    +{ name => "AltEmailAddress",       type => varchar(64), },
                    +{ name => "ExcludeFromOverdues",   type => "bool", },
                    +{ name => "SDIEmailAddress",       type => varchar(150), },
                    +{ name => "SDIEmailFormatID",      type => $idtype, },
                    +{ name => "SDIPositiveAssent",     type => "bool", },
                    +{ name => "SDIPositiveAssentDate", type => "timestamp", },
                    +{ name => "DeletionExempt",        type => "bool", },
                    +{ name => "PatronFullName",        type => varchar(100), },
                    +{ name => "ExcludeFromHolds",      type => "bool", },
                    +{ name => "ExcludeFromBills",      type => "bool", },
                    +{ name => "EmailFormatID",         type => $idtype, },
                    +{ name => "PatronFirstLastName",   type => varchar(100), },
                    +{ name => "Username",              type => varchar(50), },
                    +{ name => "MergeDate",             type => "timestamp",  }, # Polaris, AFAIK,
                    +{ name => "MergeUserID",           type => $idtype,     }, # doesn't actually
                    +{ name => "MergeBarcode",          type => varchar(20), }, # support merging.
                    +{ name => "EnableSMS",             type => "bool", },
                    +{ name => "RequestPickupBranchID", type => $idtype, },
                    +{ name => "Phone1CarrierID",       type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.SA_MobilePhoneCarriers", f => "CarrierID", r => "n-to-one", }]},
                    +{ name => "Phone2CarrierID",       type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.SA_MobilePhoneCarriers", f => "CarrierID", r => "n-to-one", }]},
                    +{ name => "Phone3CarrierID",       type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.SA_MobilePhoneCarriers", f => "CarrierID", r => "n-to-one", }]},
                    +{ name => "eReceiptOptionID",      type => $idtype, }, # TODO: no idea where this points.
                    +{ name => "TxtPhoneNumber",        type => "int2", }, # 1, 2, 3, or NULL
                    +{ name => "ExcludeFromAlmostOverdueAutoRenew", type => "bool", },
                    +{ name => "ExcludeFromPatronRecExpiration",    type => "bool", },
                    +{ name => "ExcludeFromInactivePatron",         type => "bool", },
                    +{ name => "DoNotShowEReceiptPrompt",           type => "bool", },
                  ],},
    +{ name    => "Polaris.Polaris.PatronCodes",
       idfield => "PatronCodeID",
       migrate => "full",
       fields  => [ +{ name => "PatronCodeID",          type => $idtype, },
                    +{ name => "Description",           type => varchar(80)},   ]},
    +{ name    => "Polaris.DeliveryOptions",
       idfield => "DeliveryOptionID",
       migrate => "full",
       fields  => [ +{ name => "DeliveryOptionID",      type => $idtype, },
                    +{ name => "DeliveryOption",        type => varchar(30)}, ]},
    +{ name    => "Polaris.Polaris.PatronAddresses",
       migrate => "normal",
       idfield => "PatronID", # This is not actually a record ID field (there isn't one)
                              # but will do for our purposes: getrecord() will return
                              # multiple records where appropriate.
       fields  => [ +{ name => "PatronID",              type => $idtype, },
                    +{ name => "AddressID",             type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.Addresses", f => "AddressID", }]},
                    +{ name => "AddressTypeID",         type => $idtype, },
                    # The field names here are misleading.  The AddressTypeID relates to whether the address
                    # is for use with invoices, statements, notices, or generic use (this is not exposed when
                    # editing an address); and the FreeTextLabel field holds the actual address type, which is
                    # taken from a list that is hardcoded in the Polaris staff client (Home, Work, School,
                    # Primary, Alternate, Office, or Other; it can also be the empty string or NULL).
                    +{ name => "FreeTextLabel",         type => varchar(30) },
                    +{ name => "Verified",              type => "bool", },
                    +{ name => "VerificationDate",      type => "timestamp", },
                    +{ name => "PolarisUserID",         type => $idtype, },
                  ]},
    +{ name    => "Polaris.Polaris.Addresses",
       migrate => "normal",
       idfield => "AddressID",
       fields  => [ +{ name => "AddressID",             type => $idtype, },
                    +{ name => "PostalCodeID",          type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.PostalCodes", f => "PostalCodeID", } ]},
                    +{ name => "StreetOne",             type => varchar(64) },
                    +{ name => "StreetTwo",             type => varchar(64) },
                    +{ name => "ZipPlusFour",           type => varchar(4) },
                    +{ name => "MunicipalityName",      type => varchar(64) },
                  ]},
    +{ name    => "Polaris.Polaris.AddressTypes",
       migrate => "full", # all four records, in all their irrelevant glory; why not?
       idfield => "AddressTypeID",
       fields  => [ +{ name => "AddressTypeID",         type => $idtype, },
                    +{ name => "Description",           type => varchar(80)},  ]},
    +{ name    => "Polaris.Polaris.PostalCodes",
       migrate => "normal", # Really this should be Cleaned Up before a migration.
       idfield => "PostalCodeID",
       fields  => [ +{ name => "PostalCodeID",          type => $idtype, },
                    +{ name => "PostalCode",            type => varchar(12), }, # The actual zipcode
                    +{ name => "City",                  type => varchar(32), },
                    +{ name => "State",                 type => varchar(32), },
                    +{ name => "CountryID",             type => $idtype, },
                    +{ name => "County",                type => varchar(32), }, ]},

    +{ name    => "Polaris.Polaris.PatronStops",
       migrate => "normal",
       idfield => "PatronID",  # This is not actually a record ID field (there isn't one)
                               # but will do for our purposes: getrecord() will return
                               # multiple records where appropriate, or none.
       fields  => [ +{ name => "PatronID",              type => $idtype, },
                    +{ name => "PatronStopID",          type => $idtype, },
                    +{ name => "CreationDate",          type => "timestamp", },
                    +{ name => "CreatorID",             type => $idtype, },
                    +{ name => "ModifierID",            type => $idtype, },
                    +{ name => "ModificationDate",      type => "timestamp", },
                    +{ name => "OrganizationID",        type => $idtype, },
                    +{ name => "WorkstationID",         type => $idtype, },  ]},
    +{ name    => "Polaris.Polaris.PatronStopDescriptions",
       migrate => "full",
       idfield => "PatronStopID",
       fields  => [ +{ name => "PatronStopID",          type => $idtype, },
                    +{ name => "Description",           type => varchar(80)} ]},
    +{ name    => "Polaris.Polaris.PatronFreeTextBlocks",
       migrate => "normal",
       idfield => "PatronID",
       fields  => [ +{ name => "PatronID",              type => $idtype, },
                    +{ name => "FreeTextBlock",         type => varchar(255), },
                    +{ name => "FreeTextBlockID",       type => $idtype, },
                    +{ name => "CreationDate",          type => "timestamp", },
                    +{ name => "CreatorID",             type => $idtype, },
                    +{ name => "ModifierID",            type => $idtype },
                    +{ name => "ModificationDate",      type => "timestamp" },
                    +{ name => "OrganizationID",        type => $idtype, },
                    +{ name => "WorkstationID",         type => $idtype }, ]},
    +{ name    => "Polaris.Polaris.PatronNotes",
       migrate => "normal",
       idfield => "PatronID",
       fields  => [ +{ name => "PatronID",                   type => $idtype, },
                    +{ name => "NonBlockingStatusNotes",     type => varchar(4000) },
                    +{ name => "BlockingStatusNotes",        type => varchar(4000) },
                    +{ name => "NonBlockingStatusNoteDate",  type => "timestamp", },
                    +{ name => "BlockingStatusNoteDate",     type => "timestamp", },
                    +{ name => "NonBlockingBranchID",        type => $idtype, },
                    +{ name => "NonBlockingUserID",          type => $idtype, },
                    +{ name => "NonBlockingWorkstationID",   type => $idtype, },
                    +{ name => "BlockingBranchID",           type => $idtype, },
                    +{ name => "BlockingUserID",             type => $idtype, },
                    +{ name => "BlockingWorkstationID",      type => $idtype, },       ]},
    +{ name    => "Polaris.Polaris.PatronStatClassCodes",
       migrate => "full",
       idfield => "StatisticalClassID",
       fields  => [ +{ name => "StatisticalClassID",         type => $idtype },
                    +{ name => "OrganizationID",             type => $idtype },
                    +{ name => "Description",                type => varchar(80) },    ]},
    +{ name    => "Polaris.Polaris.EmailFormat",
       migrate => "full",
       idfield => "EmailFormatID",
       fields  => [ +{ name => "EmailFormatID",              type => $idtype },
                    +{ name => "EmailFormat",                type => varchar(10) },    ]},
    +{ name    => "Polaris.Polaris.SA_MobilePhoneCarriers",
       migrate => "normal",
       idfield => "CarrierID",
       fields  => [ +{ name => "CarrierID",                  type => $idtype, },
                    +{ name => "CarrierName",                type => varchar(255), },
                    +{ name => "Email2SMSEmailAddress",      type => varchar(255), },
                    +{ name => "NumberOfDigits",             type => "int2", },
                    +{ name => "Display",                    type => "bool", },        ]},


    #####################################################################################
    ###
    ###  I T E M   D A T A
    ###
    #####################################################################################
    +{ name    => "Polaris.Polaris.CircItemRecords",
       idfield => "ItemRecordID",
       migrate => "normal",
       current => "ItemStatusDate",
       fields  => [ +{ name => "ItemRecordID",               type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.ItemRecordDetails", f => "ItemRecordID", r => "one-to-one", }]},
                    +{ name => "Barcode",                    type => varchar(20), },
                    +{ name => "ItemStatusID",               type => $idtype, },
                    +{ name => "LastCircTransactionDate",    type => "timestamp", },
                    +{ name => "AssociatedBibRecordID",      type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.BibliographicRecords", f => "BibliographicRecordID", }]},
                    +{ name => "ParentItemRecordID",         type => $idtype, },
                    +{ name => "RecordStatusID",             type => $idtype, },
                    +{ name => "AssignedbranchID",           type => $idtype, },
                    +{ name => "AssignedCollectionID",       type => $idtype, },
                    +{ name => "MaterialTypeID",             type => $idtype, },
                    +{ name => "LastUsePatronID",            type => $idtype, },
                    +{ name => "LastUseBranchID",            type => $idtype, },
                    +{ name => "YTDCircCount",               type => "int2", },
                    +{ name => "LifetimeCircCount",          type => "int4", }, # int4 is probably overkill
                    +{ name => "YTDInHouseUseCount",         type => "int2", },
                    +{ name => "LifetimeInHouseUseCount",    type => "int4", }, # ditto here
                    +{ name => "FreeTextBlock",              type => varchar(255), },
                    +{ name => "ManualBlockID",              type => $idtype,}, # links to ItemBlockDescriptions
                    +{ name => "FineCodeID",                 type => $idtype, },
                    +{ name => "LoanPeriodCodeID",           type => $idtype, },
                    +{ name => "StatisticalCodeID",          type => $idtype, },
                    +{ name => "ShelfLocationID",            type => $idtype, },
                    +{ name => "ILLFlag",                    type => "bool", },
                    +{ name => "DisplayInPAC",               type => "bool", },
                    +{ name => "RenewalLimit",               type => "int2", },
                    +{ name => "Holdable",                   type => "bool", },
                    +{ name => "HoldableByPickup",           type => "bool", },
                    +{ name => "HoldableByBranch",           type => "bool", },
                    +{ name => "HoldableByLibrary",          type => "bool", },
                    +{ name => "LoanableOutsideSystem",      type => "bool", },
                    +{ name => "NonCirculating",             type => "bool", },
                    +{ name => "RecordStatusDate",           type => "timestamp", },
                    +{ name => "LastCircWorkstationID",      type => $idtype, },
                    +{ name => "LastCircPolarisUserID",      type => $idtype, },
                    +{ name => "HoldableByPrimaryLender",    type => "bool", },
                    +{ name => "OriginalCheckOutDate",       type => "timestamp", },
                    +{ name => "OriginalDueDate",            type => "timestamp", },
                    +{ name => "ItemStatusDate",             type => "timestamp", },
                    +{ name => "CheckInBranchID",            type => $idtype, },
                    +{ name => "CheckInDate",                type => "timestamp", },
                    +{ name => "InTransitSentBranchID",      type => $idtype, },
                    +{ name => "InTransitSentDate",          type => "timestamp", },
                    +{ name => "InTransitRecvdBranchID",     type => $idtype, },
                    +{ name => "InTransitRecvdDate",         type => "timestamp", },
                    +{ name => "CheckInWorkstationID",       type => $idtype, },
                    +{ name => "CheckInUserID",              type => $idtype, },
                    +{ name => "LastCheckOutRenewDate",      type => "timestamp", },
                    +{ name => "ShelvingBit",                type => "bool", },
                    +{ name => "FirstAvailableDate",         type => "timestamp", },
                    +{ name => "LoaningOrgID",               type => $idtype, },
                    +{ name => "HomeBranchID",               type => $idtype, },
                    +{ name => "ItemDoesNotFloat",           type => "bool", },
                    +{ name => "EffectiveDisplayInPAC",      type => "bool", },
                    +{ name => "DoNotMailToPatron",          type => "bool", },
                    +{ name => "ElectronicItem",             type => "bool", },
                    +{ name => "LastDueDate",                type => "timestamp", },
                    +{ name => "ResourceEntityID",           type => $idtype, },
                    +{ name => "HoldPickupBranchID",         type => $idtype, },   ]},
    +{ name    => "Polaris.Polaris.ItemRecordDetails",
       idfield => "ItemRecordID",
       migrate => "normal",
       fields  => [ +{ name => "ItemRecordID",               type => $idtype, },
                    +{ name => "OwningBranchID",             type => $idtype, },
                    +{ name => "CreatorID",                  type => $idtype, },
                    +{ name => "ModifierID",                 type => $idtype, },
                    +{ name => "CallNumberPrefix",           type => varchar(60), },
                    +{ name => "ClassificationNumber",       type => varchar(60), },
                    +{ name => "CutterNumber",               type => varchar(60), },
                    +{ name => "CallNumberSuffix",           type => varchar(60), },
                    +{ name => "CopyNumber",                 type => varchar(60), },
                    +{ name => "VolumeNumber",               type => varchar(60), },
                    +{ name => "TemporaryShelfLocation",     type => varchar(25), },
                    +{ name => "PublicNote",                 type => varchar(255), },
                    +{ name => "NonPublicNote",              type => varchar(255), },
                    +{ name => "CreationDate",               type => "timestamp", },
                    +{ name => "ModificationDate",           type => "timestamp", },
                    +{ name => "ImportedDate",               type => "timestamp", },
                    +{ name => "LastInventoryDate",          type => "timestamp", },
                    +{ name => "Price",                      type => "money", },
                    +{ name => "ImportedBibControlNumber",   type => varchar(50), },
                    +{ name => "ImportedRecordSource",       type => varchar(50), },
                    +{ name => "PhysicalCondition",          type => varchar(255) },
                    +{ name => "NameOfPiece",                type => varchar(255) },
                    +{ name => "FundingSource",              type => varchar(50) },
                    +{ name => "AcquisitionDate",            type => "timestamp", },
                    +{ name => "ShelvingSchemeID",           type => $idtype, },
                    +{ name => "CallNumber",                 type => varchar(255) },
                    +{ name => "DonorID",                    type => $idtype, },
                    +{ name => "ImportEDIUpdateFlag",        type => "bool", },
                    +{ name => "CallNumberVolumeCopy",       type => varchar(370) },
                    +{ name => "SpecialItemCheckInNote",     type => varchar(255) },   ]},
    +{ name    => "Polaris.Polaris.ItemStatuses",
       idfield => "ItemStatusID",
       migrate => "full",
       fields  => [ +{ name => "ItemStatusID",               type => $idtype },
                    +{ name => "Description",                type => varchar(80) },
                    +{ name => "Name",                       type => varchar(25) },  ]},
    +{ name    => "Polaris.Polaris.Collections",
       migrate => "full",
       idfield => "CollectionID",
       fields  => [ +{ name => "CollectionID",               type => $idtype },
                    +{ name => "Name",                       type => varchar(80)},
                    +{ name => "Abbreviation",               type => varchar(15)},
                    +{ name => "CreatorID",                  type => $idtype},
                    +{ name => "ModifierID",                 type => $idtype},
                    +{ name => "CreationDate",               type => "timestamp"},
                    +{ name => "ModificationDate",           type => "timestamp"},    ]},
    +{ name    => "Polaris.Polaris.MaterialTypes",
       migrate => "full",
       idfield => "MaterialTypeID",
       fields  => [ +{ name => "MaterialTypeID",             type => $idtype },
                    +{ name => "Description",                type => varchar(80)},   ]},
    +{ name    => "Polaris.Polaris.MaterialLoanLimits",
       migrate => "full",
       fields  => [ +{ name => "OrganizationID",             type => $idtype },
                    +{ name => "PatronCodeID",               type => $idtype },
                    +{ name => "MaterialTypeID",             type => $idtype },
                    +{ name => "MaxItems",                   type => "int2" },
                    +{ name => "MaxRequestItems",            type => "int2" },       ]},
    +{ name    => "Polaris.Polaris.ItemBlockDescriptions",
       migrate => "full",
       idfield => "ItemBlockID",
       fields  => [ +{ name => "OrganizationID",             type => $idtype },
                    +{ name => "ItemBlockID",                type => $idtype },
                    +{ name => "Description",                type => varchar(80)},
                    +{ name => "SequenceID",                 type => "int2", },
                  ]},
    +{ name    => "Polaris.Polaris.FineCodes",
       migrate => "full",
       idfield => "FineCodeID",
       fields  => [ +{ name => "FineCodeID",                 type => $idtype },
                    +{ name => "Description",                type => varchar(80) },  ]},
    +{ name    => "Polaris.Polaris.Fines", # These are amounts for each fine code.
       migrate => "full",
       idfield => "FinesID",
       fields  => [ +{ name => "FinesID",                    type => $idtype },
                    +{ name => "OrganizationID",             type => $idtype },
                    +{ name => "PatronCodeID",               type => $idtype },
                    +{ name => "FineCodeID",                 type => $idtype },
                    +{ name => "Amount",                     type => "money" },
                    +{ name => "MaximumFine",                type => "money" },
                    +{ name => "GraceUnits",                 type => "int2" },       ]},
    +{ name    => "Polaris.Polaris.LoanPeriodCodes",
       migrate => "full",
       idfield => "LoanPeriodCodeID",
       fields  => [ +{ name => "LoanPeriodCodeID",           type => $idtype },
                    +{ name => "Description",                type => varchar(80)},   ]},
    +{ name    => "Polaris.Polaris.LoanPeriods",
       migrate => "full",
       idfield => "LPID",
       fields  => [ +{ name => "LPID",                       type => $idtype },
                    +{ name => "OrganizationID",             type => $idtype },
                    +{ name => "PatronCodeID",               type => $idtype },
                    +{ name => "LoanPeriodCodeID",           type => $idtype },
                    +{ name => "TimeUnit",                   type => $idtype },
                    +{ name => "Units",                      type => "int2" },       ]},
    +{ name    => "Polaris.Polaris.TimeUnits",
       migrate => "full",
       idfield => "TimeUnitID",
       fields  => [ +{ name => "TimeUnitID",                 type => $idtype },
                    +{ name => "Description",                type => varchar(32) },  ]},
    +{ name    => "Polaris.Polaris.StatisticalCodes",
       migrate => "full",
       idfield => "StatisticalCodeID",
       fields  => [ +{ name => "StatisticalCodeID",          type => $idtype },
                    +{ name => "OrganizationID",             type => $idtype },
                    +{ name => "Description",                type => varchar(80) },  ]},
    +{ name    => "Polaris.Polaris.ShelfLocations",
       migrate => "full",
       idfield => "ShelfLocationID",
       fields  => [ +{ name => "ShelfLocationID",            type => $idtype },
                    +{ name => "OrganizationID",             type => $idtype },
                    +{ name => "Description",                type => varchar(80) },  ]},
    +{ name    => "Polaris.Polaris.SA_MaterialTypeGroups",
       migrate => "full",
       idfield => "GroupID",
       fields  => [ +{ name => "GroupID",                    type => $idtype, },
                    +{ name => "OrganizationID",             type => $idtype, },
                    +{ name => "GroupName",                  type => varchar(80) },  ]},
    +{ name    => "Polaris.Polaris.SA_MaterialTypeGroups_Definitions",
       migrate => "full",
       idfield => "GroupID",
       fields  => [ +{ name => "GroupID",                    type => $idtype, },
                    +{ name => "MaterialTypeID",             type => $idtype, },     ]},
    +{ name    => "Polaris.Polaris.SA_MaterialTypeGroups_Limits",
       migrate => "full",
       idfield => "GroupID",
       fields  => [ +{ name => "GroupID",                    type => $idtype, },
                    +{ name => "PatronCodeID",               type => $idtype, },
                    +{ name => "Limit",                      type => "int2",
                                                             pgname => "CheckoutLimit" },
                  ]},


    #####################################################################################
    ###
    ###  B I B L I O G R A P H I C   D A T A
    ###
    #####################################################################################
    +{ name    => "Polaris.Polaris.BibliographicRecords",
       idfield => "BibliographicRecordID",
       migrate => "normal",
       fields  => [ +{ name => "BibliographicRecordID",      type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.BibliographicTOMIndex", f => "BibliographicRecordID" },
                                 +{ t => "Polaris.Polaris.BibliographicTags", f => "BibliographicRecordID" }]},
                    +{ name => "RecordStatusID",             type => $idtype },
                    +{ name => "RecordOwnerID",              type => $idtype },
                    +{ name => "CreatorID",                  type => $idtype },
                    +{ name => "ModifierID",                 type => $idtype },
                    +{ name => "BrowseAuthor",               type => varchar(255)},
                    +{ name => "BrowseTitle",                type => varchar(255)},
                    +{ name => "BrowseCallNo",               type => varchar(255)},
                    +{ name => "DisplayInPAC",               type => varchar(255)},
                    +{ name => "ImportedDate",               type => "timestamp" },
                    +{ name => "MARCBibStatus",              type => char(1)},
                    +{ name => "MARCBibType",                type => char(1)},
                    +{ name => "MARCBibLevel",               type => char(1)},
                    +{ name => "MARCTypeControl",            type => char(1)},
                    +{ name => "MARCBibEncodingLevel",       type => char(1)},
                    +{ name => "MARCDescCatalogingForm",     type => char(1)},
                    +{ name => "MARCLinkedRecordReq",        type => char(1)},
                    +{ name => "MARCPubDateOne",             type => char(4) },
                    +{ name => "MARCPubDateTwo",             type => char(4)},
                    +{ name => "MARCTargetAudience",         type => char(1)},
                    +{ name => "MARCLanguage",               type => char(3)},
                    +{ name => "MARCPubPlace",               type => char(3)},
                    +{ name => "PublicationYear",            type => "int2"},
                    +{ name => "MARCCreationDate",           type => char(6)},
                    +{ name => "MARCModificationDate",       type => varchar(16)},
                    +{ name => "MARCLCCN",                   type => varchar(40)},
                    +{ name => "MARCMedium",                 type => varchar(100)},
                    +{ name => "MARCPublicationStatus",      type => char(1)},
                    +{ name => "ILLFlag",                    type => "bool"},
                    +{ name => "MARCCharCodingScheme",       type => char(1)},
                    +{ name => "SortAuthor",                 type => varchar(255)},
                    +{ name => "LiteraryForm",               type => char(1)},
                    +{ name => "RecordStatusDate",           type => "timestamp"},
                    +{ name => "ModifiedByAuthorityJob",     type => "bool"},
                    +{ name => "PrimaryMARCTOMID",           type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.MARCTypeOfMaterial", f => "MARCTypeOfMaterialID", } ]},
                    +{ name => "FirstAvailabilityDate",      type => "timestamp"},
                    +{ name => "CreationDate",               type => "timestamp"},
                    +{ name => "ModificationDate",           type => "timestamp"},
                    +{ name => "LifetimeCircCount",          type => "int4"},
                    +{ name => "LifetimeInHouseUseCount",    type => "int4"},
                    +{ name => "SortTitle",                  type => varchar(255)},
                    +{ name => "Popularity",                 type => "int4"},
                    +{ name => "ImportedFileName",           type => varchar(255)},
                    +{ name => "BrowseTitleNonFilingCount",  type => "int2"},
                    +{ name => "ImportedControlNumber",      type => varchar(50)},
                    +{ name => "ImportedRecordSource",       type => varchar(50)},
                    +{ name => "HasElectronicURL",           type => "bool"},
                    +{ name => "DoNotOverlay",               type => "bool"},
                    +{ name => "HostBibliographicRecordID",  type => $idtype},
                    +{ name => "HasConstituents",            type => "bool"},
                    +{ name => "BoundWithCreatorID",         type => $idtype},
                    +{ name => "BoundWithCreationDate",      type => "timestamp"},   ]},
    +{ name    => "Polaris.Polaris.BibliographicTOMIndex",
       idfield => "BibliographicRecordID", # Not actually a primary key.
       migrate => "normal",
       fields  => [ +{ name => "BibliographicRecordID",      type => $idtype },
                    +{ name => "MARCTypeOfMaterialID",       type => $idtype },
                    +{ name => "SearchCode",                 type => char(3), },
                  ]},
    +{ name    => "Polaris.Polaris.MARCTypeOfMaterial",
       idfield => "MarcTypeOfMaterialID",
       migrate => "full",
       fields  => [ +{ name => "MARCTypeOfMaterialID",       type => $idtype },
                    +{ name => "Precedence",                 type => "int2", },
                    +{ name => "Description",                type => varchar(80)},
                    +{ name => "SearchCode",                 type => varchar(25)}, ]},
    +{ name    => "Polaris.Polaris.BibliographicTags",
       idfield => "BibliographicRecordID", # Not actually; but for our linking purposes.
       migrate => "normal",
       fields  => [ +{ name => "BibliographicTagID",         type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.BibliographicSubfields", f => "BibliographicTagID", }]},
                    +{ name => "BibliographicRecordID",      type => $idtype },
                    +{ name => "Sequence",                   type => "int2", },
                    +{ name => "TagNumber",                  type => "int2", },
                    +{ name => "IndicatorOne",               type => char(1) },
                    +{ name => "IndicatorTwo",               type => char(1) },
                    +{ name => "EffectiveTagNumber",         type => "int2", }, ]},
    +{ name    => "Polaris.Polaris.BibliographicSubfields",
       idfield => "BibliographicTagID", # Not actually, but for our linking purposes.
       migrate => "normal",
       fields  => [ +{ name => "BibliographicSubfieldID",     type => $idtype },
                    +{ name => "BibliographicTagID",          type => $idtype },
                    +{ name => "SubfieldSequence",            type => "int2", },
                    +{ name => "Subfield",                    type => char(1) },
                    +{ name => "Data",                        type => varchar(4000)},
                    +{ name => "NumberOfNonFilingCharacters", type => "int2", },
                  ]},


    #####################################################################################
    ###
    ###  M I S C   D A T A
    ###
    #####################################################################################
    +{ name    => "Polaris.Polaris.Organizations",
       idfield => "OrganizationID",
       migrate => "full",
       fields  => [ +{ name => "OrganizationID",         type => $idtype, },
                    +{ name => "ParentOrganizationID",   type => $idtype, },
                    +{ name => "OrganizationCodeID",     type => $idtype, },
                    +{ name => "Name",                   type => varchar(50), },
                    +{ name => "Abbreviation",           type => varchar(15), },
                    +{ name => "SA_ContactPersonID",     type => $idtype, },
                    +{ name => "CreatorID",              type => $idtype, },
                    +{ name => "ModifierID",             type => $idtype, },
                    +{ name => "CreationDate",           type => "timestamp", },
                    +{ name => "ModificationDate",       type => "timestamp", },
                    +{ name => "DisplayName",            type => varchar(50)},   ],},
    +{ name    => "Polaris.Polaris.OrganizationCodes",
       # Technically, I think this table is identical for every
       # Polaris installation, because the System Administration UI is
       # hardcoded around it being that way.  But it's tiny, so
       # whatever, there's no downside to loading it.
       idfield => "OrganizationCodeID",
       migrate => "full", # small table
       fields  => [ +{ name => "OrganizationCodeID",     type => $idtype, },
                    +{ name => "Description",            type => varchar(80), }, ]},
    +{ name    => "Polaris.Polaris.PatronReadingHistory",
       migrate => "extended",
       idfield => "PatronReadingHistoryID",
       fields  => [ +{ name => "PatronID",               type => $idtype, },
                    +{ name => "ItemRecordID",           type => $idtype, },
                    +{ name => "CheckOutDate",           type => "timestamp", },
                    +{ name => "LoaningOrgID",           type => $idtype },
                    +{ name => "BrowseAuthor",           type => varchar(255) },
                    +{ name => "BrowseTitle",            type => varchar(255), },
                    +{ name => "PrimaryMARCTOMID",       type => $idtype, },
                    +{ name => "Notes",                  type => varchar(255), },
                    +{ name => "TitleRatingID",          type => $idtype, },
                    +{ name => "PatronReadingHistoryID", type => $idtype, }
                  ]},
    +{ name    => "Polaris.Polaris.RecordStatuses",
       idfield => "RecordStatusID",
       migrate => "full",
       fields  => [ +{ name => "RecordStatusID",         type => $idtype },
                    +{ name => "RecordStatusName",       type => char(20)},  ]},
    +{ name    => "Polaris.Polaris.CourseReserves",
       # We don't actually use this table in Galion...
       idfield => "CourseReserveID",
       migrate => "normal",
       fields  => [ +{ name => "CourseReserveID",        type => $idtype, },
                    +{ name => "CreatorID",              type => $idtype, },
                    +{ name => "ModifierID",             type => $idtype, },
                    +{ name => "CreationDate",           type => "timestamp", },
                    +{ name => "ModificationDate",       type => "timestamp", },
                    +{ name => "CourseID",               type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.Courses", f => "CourseID", r => "unknown" }], },
                    +{ name => "OrganizationID",         type => $idtype, },
                    +{ name => "TermID",                 type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.CourseTerms", f => "TermID", r => "unknown"}]},
                    +{ name => "CourseStatusID",         type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.CourseStatuses", f => "CourseStatusID", r => "unknown" }]},
                    +{ name => "NumberOfStudents",       type => "int4", },
                    +{ name => "Note",                   type => varchar(255), },
                    +{ name => "CourseNumberID",         type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.CourseNumbers", f => "CourseNumberID", r => "unknown" }]},
                    +{ name => "CourseSectionID",        type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.CourseSections", f => "CourseSectionID", r => "unknown" }] },
                    +{ name => "SchoolDivisionID",       type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.SchoolDivisions", f => "SchoolDivisionID", r => "unknown" }] },
                    +{ name => "DepartmentID",           type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.Departments", f => "DepartmentID", r => "unknown" }] },
                    +{ name => "CourseNumberSection",    type => varchar(45), },
                    +{ name => "AlternateName",          type => varchar(80), },
                    +{ name => "CourseNameNumber",       type => varchar(300), },
                    +{ name => "PublicNote",             type => varchar(255), },
                  ],},
    +{ name    => "Polaris.Polaris.Donations",
       migrate => "normal",
       idfield => "DonationID",
       fields  => [ +{ name => "DonationID",             type => $idtype },
                    +{ name => "DonationCategoryID",     type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.DonationCategories", f => "DonationCategoryID", }, ]},
                    +{ name => "ReceivingOrgID",         type => $idtype },
                    +{ name => "Amount",                 type => "money" },
                    +{ name => "SendAcknowledgement",    type => "bool" },
                    +{ name => "AckName",                type => varchar(50) },
                    +{ name => "AckAddress",             type => varchar(100) },
                    +{ name => "AckCity",                type => varchar(50) },
                    +{ name => "AckStateProvinceID",     type => $idtype,
                       link => [ +{ t => "Polaris.Polaris.StatesAndProvinces", f => "StateProvinceID", r => "n-to-one" },]},
                    +{ name => "AckZip",                 type => varchar(20) },
                    +{ name => "AckEmail",               type => varchar(50) },
                    +{ name => "PurchaseTitle",          type => "bool" },
                    +{ name => "SubjectArea",            type => varchar(100) },
                    +{ name => "Processed",              type => "bool" },
                    +{ name => "ProcessedDate",          type => "timestamp" },
                    +{ name => "DonationDate",           type => "timestamp" },
                    +{ name => "ILLStoreOrderID",        type => $idtype },
                    +{ name => "DonatingPatronBardode",  type => varchar(20) },      ]},
    +{ name    => "Polaris.Polaris.DonationCategories",
       migrate => "full",
       idfield => "DonationCategoryID",
       fields  => [ +{ name => "DonationCategoryID",     type => $idtype },
                    +{ name => "Description",            type => varchar(50) },
                    +{ name => "AllowAcknowledgement",   type => "bool" },           ]},
    +{ name    => "Polaris.Polaris.Donors",
       migrate => "normal",
       idfield => "DonorID",
       fields  => [ +{ name => "DonorID",                type => $idtype },
                    +{ name => "FirstName",              type => varchar(30) },
                    +{ name => "MiddleName",             type => varchar(15) },
                    +{ name => "LastName",               type => varchar(50) },
                    +{ name => "CorporateName",          type => varchar(255) },
                    +{ name => "Phone",                  type => varchar(30) },
                    +{ name => "Fax",                    type => varchar(30) },
                    +{ name => "Email",                  type => varchar(70) },
                    +{ name => "MemorialNote",           type => varchar(255) },
                    +{ name => "DescriptionNote",        type => varchar(255) },
                    +{ name => "RestrictionNote",        type => varchar(255) },
                    +{ name => "RenewalDate",            type => "timestamp" },
                    +{ name => "AddressID",              type => $idtype },        ]},
    +{ name    => "Polaris.Polaris.Workstations",
       migrate => "full",
       idfield => "WorkstationID",
       fields  => [ +{ name => "WorkstationID",          type => $idtype },
                    +{ name => "OrganizationID",         type => $idtype },
                    +{ name => "DisplayName",            type => varchar(80) },
                    +{ name => "ComputerName",           type => varchar(32) },
                    +{ name => "CreatorID",              type => $idtype },
                    +{ name => "ModifierID",             type => $idtype },
                    +{ name => "CreationDate",           type => "timestamp" },
                    +{ name => "ModificationDate",       type => "timestamp" },
                    +{ name => "Enabled",                type => "bool" },
                    +{ name => "Status",                 type => "bool" },
                    +{ name => "StatusDate",             type => "timestamp" },
                    +{ name => "NetworkDomainID",        type => $idtype },
                    +{ name => "LeapAllowed",            type => "bool" },          ]},
    +{ name    => "Polaris.Polaris.StatesAndProvinces",
       migrate => "normal",
       idfield => "StateProvinceID",
       fields  => [ +{ name => "StateProvinceID",        type => $idtype, },
                    +{ name => "Abbreviation",           type => varchar(2), },
                    +{ name => "Description",            type => varchar(50), },
                    +{ name => "CountryID",              type => $idtype, },
                  ]},
    # TODO: for completeness, go ahead and add the following tables that we don't use in Galion:
    #    Polaris.Courses, Polaris.CourseTerms, Polaris.CourseStatuses, Polaris.CourseNumbers, Polaris.CourseSections,
    #    Polaris.SchoolDivisions, Polaris.Departments, Polaris.NetworkDomains, Polaris.Languages,
    #    Polaris.ResourceEntities, Polaris.ShelvingSchemes, Polaris.Countries,
    #    POlaris.ILLStoreOrders
  )];

sub char {
  my ($n) = @_;
  $n ||= 50;
  return "varchar($n)";
}

sub varchar {
  my ($n) = @_;
  $n ||= 50;
  return "varchar($n)";
}

sub dbconn {
  # Returns a connection to the database.
  # Used by the other functions in this file.
  return dbconn_sybase(@_);
}

sub dbconn_sybase {
  # Requires FreeTDS to be installed.
  my $server = (defined $connectinfo{sbserver}) ? qq[server=$connectinfo{sbserver}] : "server=SYBASE";
  my $host   = (defined $connectinfo{host}) ? qq[host=$connectinfo{host}] : "";
  my $port   = (defined $connectinfo{port}) ? qq[port=$connectinfo{port}] : "";
  $connectinfo{dsn} ||= "dbi:Sybase:" . (join ";", grep { $_ } ($server, $host, $port));
  my $db;
  eval {
    $db = DBI->connect($connectinfo{dsn}, $connectinfo{user}, $connectinfo{pass}, {'RaiseError' => 1})
      or die "Cannot Connect: $DBI::errstr\ndsn: $connectinfo{dsn}\n";
  };
  if ($@) {
    warn "dbconn_sybase: unable to connect with dsn '$connectinfo{dsn}', user '$connectinfo{user}' ($@)$!\n";
  }
  return $db;
}

sub dbconn_easysoft {
  # Requires a commercial Easysoft ODBC driver license.
  local $|=1;
  if (not $connectinfo{dsn}) {
    print "Did you create a dsn using the EasySoft ODBC driver installer, or in odbc.ini? (y/n)\n";
    my $yesno = <STDIN>;
    if ($yesno =~ /y/) {
      print "Enter the name of your dsn here: ";
      $connectinfo{dsn} = <STDIN>;
      chomp $connectinfo{dsn};
    } else {
      print "I'll attempt to construct a DSN the other way.\n";
      for my $field ((
                      +{ key     => "database",
                         descr   => "the name of the Polaris database",
                         default => "Polaris", },
                      +{ key     => "server",
                         descr   => "the server on which the Polaris database resides",
                         default => "GPLPRO", },
                      +{ key     => "user",
                         descr   => "the username for Polaris database access",
                         default => "polaris", },
                      +{ key     => "pass",
                         descr   => "the password for Polaris database access",},
                     )) {
        if (not $connectinfo{$$field{key}}) {
          print "Enter $$field{descr} (" . ((exists $$field{default}) ? qq[default: $$field{default}] : "[REQUIRED]") . "): ";
          $connectinfo{$$field{key}} = <STDIN>;
          chomp $connectinfo{$$field{key}};
          $connectinfo{$$field{key}} ||= $$field{default};
        }
      }
      $connectinfo{dsn} = "driver={Easysoft ODBC-SQL Server};Server=$connectinfo{server}; database=$connectinfo{database};uid=$connectinfo{user};pwd=$connectinfo{pass};";
    }
  }
  my $db = DBI->connect("dbi:ODBC:$connectinfo{dsn}", $connectinfo{user}, $connectinfo{pass}, {'RaiseError' => 1})
    or die ("Cannot Connect: $DBI::errstr\ndsn: $connectinfo{dsn}\n");
  return $db;
}

sub getsince {
  my ($table, $whenfield, $whendate, $q) = @_;
  die "Too many arguments: getsince(".(join', ',@_).")" if $q;
  my $qstring;
  my $db = dbconn();
  eval {
    $qstring = "SELECT * FROM $table WHERE $whenfield >= ?";
    $q = $db->prepare($qstring);  $q->execute(grep { $_ } ($whendate));
  }; croak("failed to execute query string '$qstring' ($whendate)") if $@;
  my @answer; my $r;
  while ($r = $q->fetchrow_hashref()) {
    if (wantarray) {
      push @answer, $r;
    } else {
      return $r;
    }
  }
  return @answer;
}

sub getrecord {
# GET:     %record  = %{getrecord(tablename, id)};
# GETALL:  @recrefs = getrecord(tablename);     # Don't use this way on enormous tables.
  my ($table, $id, $idfield, $q) = @_;
  die "Too many arguments: getrecord(".(join', ',@_).")" if $q;
  $idfield ||= 'id';
  my $qstring;
  my $db = dbconn();
  eval {
    $qstring = "SELECT * FROM $table".(($id)?" WHERE $idfield = ?":"");
    $q = $db->prepare($qstring);  $q->execute(grep { $_ } ($id));
  }; use Carp;  croak("failed to execute query string '$qstring' ($id)") if $@;
  my @answer; my $r;
  while ($r = $q->fetchrow_hashref()) {
    if (wantarray) {
      push @answer, $r;
    } else {
      return $r;
    }
  }
  return @answer;
}

sub findrecord {
# FIND:    @records = findrecord(tablename, fieldname, exact_value);
  my ($table, $field, $value, $q) = @_;
  die "Too many arguments: findrecord(".(join', ',@_).")" if $q;
  my $db = dbconn();
  $q = $db->prepare("SELECT * FROM $table WHERE $field=?");  $q->execute($value);
  my @answer; my $r;
  while ($r = $q->fetchrow_hashref()) {
    if (wantarray) {
      push @answer, $r;
    } else {
      return $r;
    }
  }
  return @answer;
}
