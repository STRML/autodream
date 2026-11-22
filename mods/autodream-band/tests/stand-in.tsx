export const standIn = (tier: 'prepend' | 'append') => ({
  name: `stand-in-${tier}`,
  tier,
  register: (on: any) => {
    on('ui.render', { component: 'AbovePrompt' }, async ($: any, e: any, next: any) => {
      const beneath = await next(e)
      const { Box, Text } = $.ui.resolve(e)

      return (
        <Box flexDirection="column">
          {beneath}
          <Text>stand-in row</Text>
        </Box>
      )
    })
  },
})
