# Every schema keyword, each one used in a small example.
@{
    '!types' = './config/Types.psm1'

    Description = 'Shows every keyword.'

    Properties = @{
        # Type, Required, Description, Pattern. Min and Max on text mean its length.
        Name = @{
            Type        = 'string'
            Required    = $true
            Description = 'Shown in error messages about this key.'
            Pattern     = '^[a-z-]+$'
            Min         = 3
            Max         = 32
        }

        # Default is used by Add-PsdDefault. Min and Max on a number mean its value.
        Port = @{ Type = 'int'; Default = 8080; Min = 1; Max = 65535 }

        # Short form: just the type.
        Enabled = 'bool'

        # Enum: only these values.
        Color = @{ Type = 'string'; Enum = 'red', 'green' }

        # Your own enum, or a type like [version].
        Level   = '[LogLevel]'
        Version = '[version]'

        # A key that can be either of two types.
        Target = @{ Type = 'string', 'map' }

        # Items on an array: a rule for every item. Max on an array means its item count.
        Tags = @{ Type = 'array'; Items = 'string'; Max = 10 }

        # Items on a map: any keys, every value must be an int.
        Quotas = @{ Type = 'map'; Items = 'int' }

        # Properties: the known keys. AllowUnknown: other keys are fine too.
        Database = @{
            Type         = 'map'
            Properties   = @{ Host = 'string'; Port = 'int' }
            AllowUnknown = $true
        }
    }
}
