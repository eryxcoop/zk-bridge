// This is a validator to be used as the policy_id of an example token named "MyCardanoToken" which will 
// be used for a demo of the milestone
validator my_token_validator {
      mint(_r, _p, _tx) {
        True
      }
}